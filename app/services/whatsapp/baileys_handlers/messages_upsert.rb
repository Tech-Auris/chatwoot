module Whatsapp::BaileysHandlers::MessagesUpsert
  include Whatsapp::BaileysHandlers::Helpers
  include Whatsapp::BaileysHandlers::Concerns::GroupContactMessageHandler
  include Whatsapp::BaileysHandlers::Concerns::IndividualContactMessageHandler
  include Whatsapp::BaileysHandlers::Concerns::GroupEventHelper
  include Whatsapp::BaileysHandlers::Concerns::GroupStubMessageHandler
  include BaileysHelper

  private

  def process_messages_upsert(messages = processed_params[:data][:messages])
    import_mode = processed_params[:importMode] == true
    messages.each do |message|
      @message = nil
      @contact_inbox = nil
      @contact = nil
      @raw_message = message
      # A history batch also carries what arrived while the connection was down. Nobody
      # has seen those yet, so they go through as live messages: AI secretary,
      # notifications and an open conversation.
      Current.history_import = import_mode && !missed_while_disconnected?(message)

      next handle_message if incoming?

      # NOTE: Shared lock with Whatsapp::SendOnWhatsappService
      # Avoids race conditions when sending messages.
      with_baileys_channel_lock_on_outgoing_message(inbox.channel.id) { handle_message }
    end
  end

  def handle_message
    @lock_acquired = false

    return handle_message_stub if message_stub?

    return if ignore_message?
    return if find_message_by_source_id(raw_message_id)

    return handle_individual_contact_message if %w[lid user].include?(jid_type)
    return handle_group_contact_message if jid_type == 'group' && inbox.channel.groups_enabled?
  end

  # Newer than the last message the inbox held when the connection came back
  # (ConnectionUpdate#coverage_until): it arrived while nobody was listening.
  def missed_while_disconnected?(message)
    covered_until = inbox.channel.provider_connection['coverage_until']
    return false if covered_until.blank?

    Time.zone.at(baileys_extract_message_timestamp(message[:messageTimestamp])) > Time.zone.parse(covered_until)
  end

  def message_stub?
    @raw_message[:messageStubType].present?
  end

  def handle_message_stub
    return unless jid_type == 'group'

    @lock_acquired = acquire_message_processing_lock
    return unless @lock_acquired

    case @raw_message[:messageStubType]
    when MEMBERSHIP_REQUEST_STUB
      handle_membership_request_stub
    when ICON_CHANGE_STUB
      handle_icon_change_stub
    when GROUP_CREATE_STUB
      handle_group_create_stub
    end
  ensure
    clear_message_source_id_from_redis if @lock_acquired
  end
end
