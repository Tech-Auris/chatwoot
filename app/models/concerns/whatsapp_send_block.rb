# Whether a WhatsApp number can send right now — the same rule the dashboard
# applies in the pencil and the reply box (dashboard/helper/whatsappHealth.js),
# for what runs on the server: macros and scheduled messages.
#
# Only a Baileys / Z-API phone that is not connected stops the send: its
# message really cannot go out. Meta's statuses on an official number are
# warnings on screen only — Meta has accepted sends while reporting the number
# as blocked, so stopping them turned working numbers away.
module WhatsappSendBlock
  def send_block_reason
    return unless provider.in?(%w[baileys zapi])
    return if provider_connection&.dig('connection') == 'open'

    provider_connection&.dig('connection') == 'connecting' ? :connecting : :disconnected
  end

  def send_block_message
    reason = send_block_reason
    I18n.t("whatsapp_send_block.#{reason}") if reason
  end
end
