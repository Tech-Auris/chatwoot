class Macros::ExecutionService < ActionService
  def initialize(macro, conversation, user)
    super(conversation)
    @macro = macro
    @account = macro.account
    @user = user
    Current.user = user
  end

  def perform
    @macro.actions.each do |action|
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def assign_agent(agent_ids)
    agent_ids = agent_ids.map { |id| id == 'self' ? @user.id : id }
    super(agent_ids)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_message(message)
    return if conversation_a_tweet?
    return note_message_not_sent if number_block_message

    params = { content: message[0], private: false }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?
    return note_message_not_sent if number_block_message

    return unless @macro.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  # A number that cannot send right now would only fail the message: the
  # macro runs its other actions and leaves a private note saying why.
  def number_block_message
    channel = @conversation.inbox.channel
    return unless channel.respond_to?(:send_block_message)

    @number_block_message ||= channel.send_block_message(starts_conversation: false)
  end

  def note_message_not_sent
    content = I18n.t('macros.message_not_sent', name: @macro.name, reason: number_block_message)
    Messages::MessageBuilder.new(@user, @conversation.reload, { content: content, private: true }).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(
      event: 'macro.executed',
      macro: { id: @macro.id, name: @macro.name },
      executed_by: @user&.webhook_data
    )
    WebhookJob.perform_later(webhook_url.first, payload)
  end
end
