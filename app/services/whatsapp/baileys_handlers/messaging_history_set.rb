# WhatsApp's history dump, forwarded by the bridge in frames when the inbox has no history
# import. After a reconnect it replays what arrived while the connection was down, and
# those messages exist nowhere else: they used to be dropped here as an unsupported event.
# Only what is newer than the last message the inbox held when the connection came back
# goes through, as live messages. The rest (a pairing's dump of recent chats) is history
# this inbox never asked to import.
module Whatsapp::BaileysHandlers::MessagingHistorySet
  private

  def process_messaging_history_set
    missed = Array(processed_params.dig(:data, :messages)).select { |message| missed_while_disconnected?(message) }
    return if missed.empty?

    process_messages_upsert(missed.sort_by { |message| baileys_extract_message_timestamp(message[:messageTimestamp]) })
  end
end
