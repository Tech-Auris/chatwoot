class SendReplyJob < ApplicationJob
  queue_as :high

  # Meta's WhatsApp Cloud API returns a small set of "please try again"
  # errors on transient hiccups (their downtime, quick rate-limit blips).
  # Retry with a bounded backoff so the operator does not have to
  # hand-retry every time Meta blips for a few seconds. Only after the
  # window is exhausted do we mark the message as failed with the last
  # error we saw.
  retry_on ::Whatsapp::Providers::TransientError,
           attempts: 3,
           wait: ->(executions) { [5, 15].fetch(executions - 1, 15).seconds } do |job, error|
    fail_message(job.arguments.first, error.meta_message)
  end

  # Retryable WhatsApp (Baileys) send errors: timeouts, a stalled connection, the provider being
  # unavailable. When the attempts run out the message must not be left on "sent", so it is
  # marked failed with the reason. Disjoint from TransientError (Cloud) above.
  #
  # Declared BEFORE the MessageAlreadyProcessing handler: retry_on is built on rescue_from,
  # which tries the LAST matching declaration first, so a broad class declared after a
  # specific one would shadow it.
  retry_on ::Whatsapp::Providers::Errors::Error, wait: :polynomially_longer, attempts: 4 do |job, error|
    Rails.logger.error "SendReplyJob exhausted retries for message #{job.arguments.first}: #{error.message}"
    fail_message(job.arguments.first, error.message)
  end

  # baileys-api answers 409 while another worker holds the idempotency lock for this message.
  # A longer, fixed wait keeps the conflict from burning the retries before the lock clears.
  retry_on ::Whatsapp::Providers::Errors::MessageAlreadyProcessing, wait: 60.seconds, attempts: 3 do |job, error|
    Rails.logger.error "SendReplyJob gave up on message #{job.arguments.first}: still processing elsewhere"
    fail_message(job.arguments.first, error.message)
  end

  def self.fail_message(message_id, reason)
    Message.find_by(id: message_id)&.update_under_lock!(status: :failed, external_error: reason)
  end

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => '::Twitter::SendOnTwitterService',
    'Channel::TwilioSms' => '::Twilio::SendOnTwilioService',
    'Channel::Line' => '::Line::SendOnLineService',
    'Channel::Telegram' => '::Telegram::SendOnTelegramService',
    'Channel::Whatsapp' => '::Whatsapp::SendOnWhatsappService',
    'Channel::Sms' => '::Sms::SendOnSmsService',
    'Channel::Instagram' => '::Instagram::SendOnInstagramService',
    'Channel::Tiktok' => '::Tiktok::SendOnTiktokService',
    'Channel::Email' => '::Email::SendOnEmailService',
    'Channel::WebWidget' => '::Messages::SendEmailNotificationService',
    'Channel::Api' => '::Messages::SendEmailNotificationService'
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    channel_name = message.conversation.inbox.channel.class.to_s

    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class_name = CHANNEL_SERVICES[channel_name]
    return unless service_class_name

    service_class_name.constantize.new(message: message).perform
  end

  private

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
