require 'rails_helper'

RSpec.describe SendReplyJob do
  subject(:job) { described_class.perform_later(message) }

  let(:message) { create(:message) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(message)
      .on_queue('high')
  end

  context 'when the job is triggered on a new message' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    def expect_mapped_service_to_perform(message, service_class_name)
      channel_name = message.conversation.inbox.channel.class.name
      mapped_class_name = described_class::CHANNEL_SERVICES.fetch(channel_name)

      expect(mapped_class_name).to eq("::#{service_class_name}")
      expect(mapped_class_name.constantize).to receive(:new).with(message: message).and_return(process_service)
      expect(process_service).to receive(:perform)

      described_class.perform_now(message.id)
    end

    it 'calls Facebook::SendOnFacebookService when its facebook message' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      message = create(:message, conversation: create(:conversation, inbox: facebook_inbox))
      allow(Facebook::SendOnFacebookService).to receive(:new).with(message: message).and_return(process_service)
      expect(Facebook::SendOnFacebookService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Twitter::SendOnTwitterService when its twitter message' do
      twitter_channel = create(:channel_twitter_profile)
      twitter_inbox = create(:inbox, channel: twitter_channel)
      message = create(:message, conversation: create(:conversation, inbox: twitter_inbox))
      expect_mapped_service_to_perform(message, 'Twitter::SendOnTwitterService')
    end

    it 'calls ::Twilio::SendOnTwilioService when its twilio message' do
      twilio_channel = create(:channel_twilio_sms)
      message = create(:message, conversation: create(:conversation, inbox: twilio_channel.inbox))
      expect_mapped_service_to_perform(message, 'Twilio::SendOnTwilioService')
    end

    it 'calls ::Telegram::SendOnTelegramService when its telegram message' do
      telegram_channel = create(:channel_telegram)
      message = create(:message, conversation: create(:conversation, inbox: telegram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Telegram::SendOnTelegramService')
    end

    it 'calls ::Line:SendOnLineService when its line message' do
      line_channel = create(:channel_line)
      message = create(:message, conversation: create(:conversation, inbox: line_channel.inbox))
      expect_mapped_service_to_perform(message, 'Line::SendOnLineService')
    end

    it 'calls ::Whatsapp:SendOnWhatsappService when its whatsapp message' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      whatsapp_channel = create(:channel_whatsapp, sync_templates: false)
      message = create(:message, conversation: create(:conversation, inbox: whatsapp_channel.inbox))
      expect_mapped_service_to_perform(message, 'Whatsapp::SendOnWhatsappService')
    end

    it 'calls ::Sms::SendOnSmsService when its sms message' do
      sms_channel = create(:channel_sms)
      message = create(:message, conversation: create(:conversation, inbox: sms_channel.inbox))
      expect_mapped_service_to_perform(message, 'Sms::SendOnSmsService')
    end

    it 'calls ::Instagram::Direct::SendOnInstagramService when its instagram message' do
      instagram_channel = create(:channel_instagram)
      message = create(:message, conversation: create(:conversation, inbox: instagram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Instagram::SendOnInstagramService')
    end

    it 'calls ::Instagram::Messenger::SendOnInstagramService when its an instagram_direct_message from facebook channel' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      conversation = create(:conversation,
                            inbox: facebook_inbox,
                            additional_attributes: { 'type' => 'instagram_direct_message' })
      message = create(:message, conversation: conversation)

      allow(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message).and_return(process_service)
      expect(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Email::SendOnEmailService when its email message' do
      email_channel = create(:channel_email)
      message = create(:message, conversation: create(:conversation, inbox: email_channel.inbox))
      expect_mapped_service_to_perform(message, 'Email::SendOnEmailService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its webwidget message' do
      webwidget_channel = create(:channel_widget)
      message = create(:message, conversation: create(:conversation, inbox: webwidget_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its api channel message' do
      api_channel = create(:channel_api)
      message = create(:message, conversation: create(:conversation, inbox: api_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Tiktok::SendOnTiktokService when its tiktok message' do
      tiktok_channel = create(:channel_tiktok)
      message = create(:message, conversation: create(:conversation, inbox: tiktok_channel.inbox))
      expect_mapped_service_to_perform(message, 'Tiktok::SendOnTiktokService')
    end
  end

  # Real prod case: Meta returned `(#131000) Something went wrong` on a
  # send; the previous behaviour marked the message failed immediately
  # and forced the operator to hand-retry. Chatwoot now retries the job
  # for a bounded window and only marks the message failed after the
  # window is exhausted.
  describe 'retry on Whatsapp::Providers::TransientError' do
    let(:whatsapp_channel) { create(:channel_whatsapp, validate_provider_config: false, sync_templates: false) }
    let(:whatsapp_message) { create(:message, conversation: create(:conversation, inbox: whatsapp_channel.inbox)) }

    it 'marks the message failed once the retry budget is exhausted' do
      failing_service = instance_double(Whatsapp::SendOnWhatsappService)
      allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(failing_service)
      allow(failing_service).to receive(:perform)
        .and_raise(Whatsapp::Providers::TransientError.new(error_code: '131000', meta_message: 'Something went wrong'))

      perform_enqueued_jobs(only: described_class) do
        described_class.perform_later(whatsapp_message.id)
      end

      whatsapp_message.reload
      expect(whatsapp_message.status).to eq('failed')
      expect(whatsapp_message.external_error).to eq('Something went wrong')
    end

    it 'stops retrying and leaves the message intact once the provider succeeds on a later attempt' do
      call_count = 0
      transient = Whatsapp::Providers::TransientError.new(error_code: '131000', meta_message: 'Something went wrong')
      service = instance_double(Whatsapp::SendOnWhatsappService)
      allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(service)
      allow(service).to receive(:perform) do
        call_count += 1
        raise transient if call_count == 1
      end

      perform_enqueued_jobs(only: described_class) do
        described_class.perform_later(whatsapp_message.id)
      end

      expect(call_count).to be > 1
      expect(whatsapp_message.reload.status).not_to eq('failed')
    end
  end

  describe 'retry on classified WhatsApp send errors' do
    let(:whatsapp_channel) { create(:channel_whatsapp, validate_provider_config: false, sync_templates: false) }
    let!(:whatsapp_message) do
      create(:message, message_type: :outgoing, conversation: create(:conversation, inbox: whatsapp_channel.inbox))
    end
    let(:service) { instance_double(Whatsapp::SendOnWhatsappService) }

    before { allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(service) }

    it 'marks the message failed with the reason once the retries run out' do
      allow(service).to receive(:perform).and_raise(Whatsapp::Providers::Errors::SendStalled, 'not accepting sends')

      perform_enqueued_jobs(only: described_class) { described_class.perform_later(whatsapp_message.id) }

      expect(whatsapp_message.reload.status).to eq('failed')
      expect(whatsapp_message.external_error).to eq('not accepting sends')
    end

    it 'retries a retryable error with a short first backoff' do
      allow(service).to receive(:perform).and_raise(Whatsapp::Providers::Errors::SendTimeout, 'timed out')

      expect { described_class.perform_now(whatsapp_message.id) }.to have_enqueued_job(described_class)
      expect(whatsapp_message.reload.status).not_to eq('failed')
    end

    # Asserted on the scheduled retry rather than on the handler list: retry_on is built on
    # rescue_from, which tries the last declaration first, so the broad Errors::Error handler
    # shadows this one unless it is declared before it.
    it 'gives a processing conflict its own, longer backoff' do
      allow(service).to receive(:perform).and_raise(Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError)

      expect { described_class.perform_now(whatsapp_message.id) }.to have_enqueued_job(described_class)

      retry_job = enqueued_jobs.reverse.find { |job| job[:job] == described_class }
      expect(retry_job[:at] - Time.zone.now.to_f).to be > 30
    end

    it 'ignores a message that no longer exists' do
      expect { described_class.fail_message(-1, 'gone') }.not_to raise_error
    end
  end
end
