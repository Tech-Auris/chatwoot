# Imports the chat history a WhatsApp Business app number shares when it is
# onboarded by coexistence (webhook field `history`, asked for by
# Channels::Whatsapp::CoexistenceSyncRequestJob). A webhook carries one of:
#
# - `history[].threads[].messages[]`: a chunk of past messages, one thread per
#   contact. Messages older than MAX_DAYS before the request are dropped.
# - `history[].errors[]` with DECLINED_ERROR_CODE: the business chose not to
#   share its history.
# - `messages[]`: the media of a message imported earlier as a placeholder
#   (Meta only sends it for media from the last 14 days).
#
# Everything runs under `Current.history_import`, so neither the conversations
# nor the messages reach the AI secretary, webhooks, automations, notifications
# or auto-assignment. Each contact's history goes into its existing conversation
# in the inbox, or into a new one created resolved.
class Whatsapp::CloudHistoryImportService
  include ::Whatsapp::IncomingMessageServiceHelpers

  MAX_DAYS = 90
  DECLINED_ERROR_CODE = 2_593_109
  # Meta spreads the chunks further apart than the Baileys node does.
  IDLE_WINDOW = 10.minutes
  MEDIA_TYPES = %w[image video audio document sticker].freeze

  pattr_initialize [:inbox!, :value!]

  def perform
    Current.history_import = true
    return record_declined if declined?
    return attach_media_files if value[:messages].present?

    import_chunks
  ensure
    Current.history_import = nil
  end

  private

  def channel
    @channel ||= inbox.channel
  end

  def declined?
    Array(value[:history]).any? { |chunk| Array(chunk[:errors]).any? { |error| error[:code].to_i == DECLINED_ERROR_CODE } }
  end

  def record_declined
    channel.with_lock { channel.update_history_import_state!('status' => 'declined', 'finished_at' => Time.current.iso8601) }
  end

  def import_chunks
    imported = Array(value[:history]).sum do |chunk|
      Array(chunk[:threads]).sum { |thread| import_thread(thread) }
    end
    track_progress(imported)
  end

  def import_thread(thread)
    phone = thread[:id].to_s
    messages = Array(thread[:messages]).select { |message| importable?(message) }
    return 0 if phone.blank? || messages.empty?

    times = messages.map { |message| message_time(message) }
    conversation = find_or_create_conversation(phone, times.min)
    imported = messages.count { |message| create_message(conversation, message) }
    bump_last_activity(conversation, times.max)
    imported
  end

  def importable?(message)
    message[:id].present? && message[:type] != 'reaction' && message_time(message) >= cutoff
  end

  def cutoff
    @cutoff ||= begin
      requested_at = channel.history_import_state&.dig('requested_at')
      (requested_at.present? ? Time.zone.parse(requested_at) : Time.current) - MAX_DAYS.days
    end
  end

  def message_time(message)
    Time.zone.at(message[:timestamp].to_i)
  end

  # Locked like a live message, so a patient writing in during the import
  # doesn't end up with two conversations.
  def find_or_create_conversation(phone, oldest_time)
    with_contact_lock(phone) do
      contact_inbox = ::ContactInboxWithContactBuilder.new(
        source_id: processed_waid(phone),
        inbox: inbox,
        contact_attributes: { name: "+#{phone}", phone_number: "+#{phone}" }
      ).perform

      inbox.conversations.where(contact_id: contact_inbox.contact_id).last ||
        create_conversation(contact_inbox, oldest_time)
    end
  end

  def create_conversation(contact_inbox, oldest_time)
    conversation = ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status: :resolved,
      created_at: oldest_time,
      last_activity_at: oldest_time
    )
    conversation.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def create_message(conversation, message)
    return false if inbox.messages.exists?(source_id: message[:id])

    outgoing = message[:from].to_s == business_number
    time = message_time(message)
    conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: outgoing ? :outgoing : :incoming,
      status: outgoing ? :delivered : :sent,
      sender: outgoing ? nil : conversation.contact,
      source_id: message[:id],
      content: imported_content(message),
      content_attributes: imported_content_attributes(message, outgoing),
      created_at: time,
      updated_at: time,
      skip_message_flooding_validation: true
    )
    true
  end

  def imported_content(message)
    return I18n.t('conversations.messages.whatsapp.history_media_unavailable') if message[:type] == 'media_placeholder'

    message_content(message).presence || I18n.t('conversations.messages.whatsapp.unsupported_message')
  end

  def imported_content_attributes(message, outgoing)
    attributes = { external_created_at: message[:timestamp].to_i, history_import: true }
    attributes[:external_echo] = true if outgoing
    attributes[:history_media_pending] = true if message[:type] == 'media_placeholder'
    attributes
  end

  def bump_last_activity(conversation, newest_time)
    last_activity_at = [conversation.last_activity_at, newest_time].compact.max
    conversation.update_columns(last_activity_at: last_activity_at) # rubocop:disable Rails/SkipsModelValidations
  end

  def business_number
    @business_number ||= channel.phone_number.delete('+')
  end

  def attach_media_files
    value[:messages].each do |media_message|
      message = inbox.messages.find_by(source_id: media_message[:id])
      payload = media_message[media_message[:type]&.to_sym]
      next if message.blank? || payload.blank? || MEDIA_TYPES.exclude?(media_message[:type])

      attach_media_file(message, media_message[:type], payload)
    end
  end

  def attach_media_file(message, type, payload)
    file = download_media(payload[:id])
    return if file.blank?

    message.attachments.new(
      account_id: message.account_id,
      file_type: file_content_type(type),
      file: { io: file, filename: payload[:filename].presence || file.original_filename, content_type: file.content_type }
    )
    message.content = payload[:caption]
    message.content_attributes = message.content_attributes.except(:history_media_pending, 'history_media_pending')
    message.save!
  end

  def download_media(media_id)
    url_response = HTTParty.get(channel.media_url(media_id), headers: channel.api_headers)
    return unless url_response.success?

    Down.download(url_response.parsed_response['url'], headers: channel.api_headers)
  end

  def track_progress(imported)
    now = Time.current.iso8601
    channel.with_lock do
      state = channel.history_import_state || {}
      channel.update_history_import_state!(
        'status' => 'in_progress',
        'started_at' => state['started_at'] || now,
        'last_batch_at' => now,
        'processed_batches' => state.fetch('processed_batches', 0) + 1,
        'messages_imported' => state.fetch('messages_imported', 0) + imported,
        'finished_at' => nil
      )
    end
    Channels::Whatsapp::BaileysHistoryImportFinalizeJob.set(wait: IDLE_WINDOW + 1.minute).perform_later(channel.id, IDLE_WINDOW.to_i)
  end
end
