# Super Admin → Settings → Google: connects the Google account the clinics
# share their calendars with, for the ERP → Agenda screen (Agenda::GoogleConnection).
class SuperAdmin::Integrations::AgendaGoogleController < SuperAdmin::ApplicationController
  STATE = :agenda_google_state

  def connect
    session[STATE] = SecureRandom.hex(16)
    redirect_to Agenda::GoogleConnection.authorize_url(redirect_uri: self.class.callback_url(request), state: session[STATE]),
                allow_other_host: true
  end

  def callback
    return back_to_settings(alert: "O Google não autorizou a conexão: #{params[:error]}") if params[:error].present?
    return back_to_settings(alert: 'A resposta do Google não veio desta tela. Tente conectar de novo.') unless valid_state?

    Agenda::GoogleConnection.connect!(code: params[:code], redirect_uri: self.class.callback_url(request))
    back_to_settings(success: "Conta Google conectada: #{Agenda::GoogleConnection.email}.")
  rescue Agenda::Source::Error => e
    back_to_settings(alert: "Não foi possível conectar a conta Google: #{e.message}")
  end

  def test_connection
    Agenda::GoogleConnection.access_token
    back_to_settings(success: "Conexão com a conta Google #{Agenda::GoogleConnection.email} OK.")
  rescue Agenda::Source::Error => e
    back_to_settings(alert: "Conexão com a conta Google falhou: #{e.message}")
  end

  def disconnect
    Agenda::GoogleConnection.disconnect!
    back_to_settings(success: 'Conta Google desconectada. A agenda das clínicas do Google Calendar para de aparecer até conectar de novo.')
  end

  # Registered as an authorized redirect URI of the installation's Google OAuth app.
  def self.callback_url(request)
    "#{ENV.fetch('FRONTEND_URL', request.base_url).chomp('/')}/super_admin/integrations/agenda_google/callback"
  end

  private

  def valid_state?
    expected = session.delete(STATE)
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
  end

  def back_to_settings(flash)
    redirect_to super_admin_app_config_path(config: 'google'), flash: flash
  end
end
