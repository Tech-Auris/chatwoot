class ScheduledMessages::SendScheduledMessageJob < ApplicationJob
  include Events::Types

  queue_as :medium

  def perform(scheduled_message_id)
    scheduled_message = ScheduledMessage.find_by(id: scheduled_message_id)
    return unless scheduled_message

    Current.executed_by = scheduled_message.author if scheduled_message.author.is_a?(AutomationRule)
    scheduled_message.with_lock { send_if_ready(scheduled_message) }
  rescue StandardError => e
    Rails.logger.error("Scheduled message #{scheduled_message_id} failed: #{e.class} #{e.message}")
    if scheduled_message&.pending?
      scheduled_message.update!(status: :failed)
      dispatch_event(scheduled_message)
      handle_recurrence_on_failure(scheduled_message)
    end
  ensure
    Current.reset
  end

  private

  def send_if_ready(scheduled_message)
    return unless scheduled_message.pending?
    return unless scheduled_message.due_for_sending?
    return fail_for_unusable_number(scheduled_message) if number_block_message(scheduled_message)

    message = send_message(scheduled_message)
    update_scheduled_message_status(scheduled_message, message)
    handle_recurrence(scheduled_message)
  end

  def send_message(scheduled_message)
    params = {
      content: scheduled_message.content,
      private: false,
      message_type: 'outgoing',
      scheduled_message: scheduled_message
    }
    params[:template_params] = scheduled_message.template_params if scheduled_message.template_params.present?
    params[:attachments] = [scheduled_message.attachment.blob.signed_id] if scheduled_message.attachment.attached?
    params.merge!(scheduled_message_content_attributes(scheduled_message))

    Messages::MessageBuilder.new(message_author(scheduled_message), scheduled_message.conversation, params).perform
  end

  # The conversation is already open, so a RESTRICTED number may still send.
  def number_block_message(scheduled_message)
    channel = scheduled_message.inbox.channel
    return unless channel.respond_to?(:send_block_message)

    @number_block_message ||= channel.send_block_message(starts_conversation: false)
  end

  # A number that cannot send at the scheduled time would only fail the
  # message: the schedule fails with the reason, the author is told through a
  # private note that mentions them (the usual mention notification), and a
  # recurring series moves on to its next date.
  def fail_for_unusable_number(scheduled_message)
    reason = number_block_message(scheduled_message)
    scheduled_message.update!(status: :failed, failure_reason: reason)
    dispatch_event(scheduled_message)
    note_author_of_failure(scheduled_message, reason)
    handle_recurrence_on_failure(scheduled_message)
  end

  def note_author_of_failure(scheduled_message, reason)
    author = scheduled_message.author
    mention = author.is_a?(User) ? "[@#{author.name}](mention://user/#{author.id}/#{ERB::Util.url_encode(author.name)}) " : ''
    I18n.with_locale(scheduled_message.account.locale) do
      scheduled_message.conversation.messages.create!(
        account: scheduled_message.account, inbox: scheduled_message.inbox, message_type: :outgoing, private: true,
        content: "#{mention}#{I18n.t('scheduled_messages.not_sent', reason: reason)}"
      )
    end
  end

  def message_author(scheduled_message)
    scheduled_message.author.is_a?(User) ? scheduled_message.author : nil
  end

  def scheduled_message_content_attributes(scheduled_message)
    return {} unless scheduled_message.author.is_a?(AutomationRule)

    { content_attributes: { automation_rule_id: scheduled_message.author_id } }
  end

  def update_scheduled_message_status(scheduled_message, message)
    return unless scheduled_message.pending?

    new_status = message.failed? ? :failed : :sent
    return if scheduled_message.status == new_status.to_s

    scheduled_message.update!(status: new_status, message: message)
    dispatch_event(scheduled_message)
  end

  def dispatch_event(scheduled_message)
    Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: scheduled_message)
  end

  def handle_recurrence(scheduled_message)
    return if scheduled_message.recurring_scheduled_message_id.blank?

    recurring = scheduled_message.recurring_scheduled_message
    return unless recurring&.active?

    RecurringScheduledMessages::CreateNextOccurrenceService.new(
      recurring_scheduled_message: recurring,
      previous_scheduled_message: scheduled_message
    ).perform
  end

  def handle_recurrence_on_failure(scheduled_message)
    return if scheduled_message.recurring_scheduled_message_id.blank?

    recurring = scheduled_message.recurring_scheduled_message
    return unless recurring&.active?

    next_message = RecurringScheduledMessages::CreateNextOccurrenceService.new(
      recurring_scheduled_message: recurring,
      previous_scheduled_message: scheduled_message,
      skip_increment: true
    ).perform

    create_failure_activity_message(scheduled_message, next_message) if next_message
  end

  def create_failure_activity_message(scheduled_message, next_message)
    I18n.with_locale(scheduled_message.account.locale) do
      scheduled_message.conversation.messages.create!(
        account: scheduled_message.account,
        inbox: scheduled_message.inbox,
        message_type: :activity,
        content: I18n.t(
          'conversations.activity.recurring_message_failed',
          next_date: next_message.scheduled_at.in_time_zone(scheduled_message.account.reporting_timezone || 'UTC').strftime('%d/%m/%Y %H:%M')
        )
      )
    end
  end
end
