# Super Admin → Settings → Autentique: proves the token works and shows whose
# Autentique account it is — that person signs every contract for Auris.
class SuperAdmin::Integrations::AutentiqueController < SuperAdmin::ApplicationController
  def test_connection
    me = Integrations::Autentique::Client.new.me
    redirect_to super_admin_app_config_path(config: 'autentique'),
                flash: { success: "Conexão com o Autentique OK — os contratos serão assinados por #{me['name']} (#{me['email']})." }
  rescue Integrations::Autentique::Client::Unauthorized => e
    redirect_to super_admin_app_config_path(config: 'autentique'), alert: "Token do Autentique inválido: #{e.message}"
  rescue Integrations::Autentique::Client::Error => e
    redirect_to super_admin_app_config_path(config: 'autentique'), alert: "Não foi possível falar com o Autentique: #{e.message}"
  end
end
