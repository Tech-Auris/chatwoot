# One-off actions for the Stripe integration surfaced under
# Super Admin → Settings → Stripe. The key itself is saved by the shared
# app_configs form; this controller only proves the credential works.
class SuperAdmin::Integrations::StripeController < SuperAdmin::ApplicationController
  MODE_LABELS = {
    test: 'modo TESTE',
    live: 'modo LIVE',
    unknown: 'modo não identificado'
  }.freeze

  def test_connection
    client = Integrations::Stripe::Client.new
    account = client.account

    redirect_to super_admin_app_config_path(config: 'stripe'),
                flash: { success: "Conexão com o Stripe OK — #{account_label(account, client)}." }
  rescue Integrations::Stripe::Client::Unauthorized => e
    redirect_to super_admin_app_config_path(config: 'stripe'), alert: "Credencial do Stripe inválida: #{e.message}"
  rescue Integrations::Stripe::Client::Error, StandardError => e
    redirect_to super_admin_app_config_path(config: 'stripe'), alert: "Não foi possível falar com o Stripe: #{e.message}"
  end

  private

  # The mode matters more than the name: a test key silently doing nothing in
  # production is the failure this screen exists to catch.
  #
  # `to_hash` because StripeObject has no `dig` — it resolves attributes
  # through method_missing, so digging into the nested settings raises.
  def account_label(account, client)
    name = account.to_hash.dig(:settings, :dashboard, :display_name).presence || account.id
    "#{name} (#{MODE_LABELS.fetch(client.key_mode)})"
  end
end
