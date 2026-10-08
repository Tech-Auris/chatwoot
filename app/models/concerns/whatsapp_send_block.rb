# Whether a WhatsApp number can send right now — the same rule the dashboard
# applies in the pencil and the reply box (dashboard/helper/whatsappHealth.js),
# for what runs on the server: macros, scheduled messages, campaigns.
#
# Baileys / Z-API: only a connected phone sends. Official API: Meta's own
# `health_status` (BLOCKED) wins, then the number's status; a REJECTED account
# review alone does not block. RESTRICTED (new-contact limit reached) only
# stops what starts a conversation. A number not read yet is let through.
module WhatsappSendBlock
  BLOCKING_PHONE_STATUSES = {
    'BANNED' => :banned, 'DISCONNECTED' => :number_disconnected, 'DELETED' => :deleted,
    'PENDING' => :pending, 'UNVERIFIED' => :pending
  }.freeze

  def send_block_reason(starts_conversation: true)
    return unofficial_send_block_reason if provider.in?(%w[baileys zapi])

    health = provider_connection&.dig('health')
    return if health.blank?
    return :meta_blocked if health['can_send_message'] == 'BLOCKED'
    return :restricted if health['phone_status'] == 'RESTRICTED' && starts_conversation

    BLOCKING_PHONE_STATUSES[health['phone_status']]
  end

  # The reason in words, with Meta's own explanation when Meta blocks it.
  def send_block_message(starts_conversation: true)
    reason = send_block_reason(starts_conversation: starts_conversation)
    return if reason.nil?

    I18n.t("whatsapp_send_block.#{reason}")
  end

  private

  def unofficial_send_block_reason
    return if provider_connection&.dig('connection') == 'open'

    provider_connection&.dig('connection') == 'connecting' ? :connecting : :disconnected
  end
end
