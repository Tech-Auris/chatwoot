# Tells the Auris team on ClickUp that Meta rejected a kit template. The
# comment goes on the deal task of the proposal that became the account or,
# for accounts that did not come from a sale, on the fixed alert task set in
# Super Admin (CLICKUP_TEMPLATE_ALERT_TASK_ID). With neither, it is only logged.
class Whatsapp::TemplateRejectedClickupJob < ApplicationJob
  queue_as :low
  retry_on Integrations::Clickup::Client::ProviderUnavailable, wait: :polynomially_longer, attempts: 5
  discard_on Integrations::Clickup::Client::Unauthorized do |_job, error|
    Rails.logger.error("[TemplateKit] ClickUp rejected the credentials: #{error.message}")
  end

  def perform(channel, template_id, reason)
    template = Array(channel.message_templates).find { |t| t.is_a?(Hash) && t['id'].to_s == template_id }
    return if template.nil?

    task_id = target_task_id(channel.account_id)
    client = Integrations::Clickup::Client.new
    if task_id.blank? || !client.configured?
      Rails.logger.warn("[TemplateKit] account=#{channel.account_id} #{template['name']} rejected (#{reason}), no ClickUp task to alert")
      return
    end

    client.add_comment(task_id, comment(channel, template, reason))
  end

  private

  def target_task_id(account_id)
    SalesQuote.where(account_id: account_id).converted.order(:updated_at).last&.clickup_task_id.presence ||
      GlobalConfig.get('CLICKUP_TEMPLATE_ALERT_TASK_ID')['CLICKUP_TEMPLATE_ALERT_TASK_ID'].presence
  end

  def comment(channel, template, reason)
    account = channel.inbox.account
    [
      '⚠️ Template rejeitado pela Meta',
      "Conta: #{account.name} (##{account.id})",
      "Número: #{channel.inbox.name} (#{channel.phone_number})",
      "Template: #{template['name']}",
      "Motivo: #{reason.presence || template['rejected_reason'].presence || 'não informado'}",
      "Abrir no AurisChat: #{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{account.id}/settings/meta-templates"
    ].join("\n")
  end
end
