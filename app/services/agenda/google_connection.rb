# The one Google account the clinics share their Google calendars with,
# connected once in Super Admin → Settings → Google (read-only calendar scope).
# The agenda of every Google Calendar account is read with it; there's no
# login per clinic.
#
# Uses the installation's Google OAuth app (GOOGLE_OAUTH_CLIENT_ID/SECRET) and
# keeps the refresh token and the account's e-mail in installation configs. A
# refresh token Google stops accepting (revoked, or the app is still in the
# "Testing" publishing status, where tokens last 7 days) raises Error with a
# message telling to reconnect, both on the agenda screen and in Super Admin.
class Agenda::GoogleConnection
  class Error < Agenda::Source::Error; end

  REFRESH_TOKEN = 'AGENDA_GOOGLE_REFRESH_TOKEN'.freeze
  EMAIL = 'AGENDA_GOOGLE_EMAIL'.freeze
  SCOPE = 'openid email https://www.googleapis.com/auth/calendar.readonly'.freeze
  AUTHORIZE_URL = 'https://accounts.google.com/o/oauth2/v2/auth'.freeze
  TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  USERINFO_URL = 'https://openidconnect.googleapis.com/v1/userinfo'.freeze
  ACCESS_TOKEN_TTL = 50.minutes
  HTTP_TIMEOUT = 15

  class << self
    def email
      InstallationConfig.find_by(name: EMAIL)&.value.presence
    end

    def connected?
      refresh_token.present?
    end

    def authorize_url(redirect_uri:, state:)
      query = { client_id: client_id, redirect_uri: redirect_uri, response_type: 'code', scope: SCOPE, state: state,
                access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true' }
      "#{AUTHORIZE_URL}?#{query.to_query}"
    end

    # Trades the code Google sent back for a refresh token, and keeps it with
    # the e-mail of the account that authorized.
    def connect!(code:, redirect_uri:)
      tokens = token_request(grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri)
      raise Error, I18n.t('agenda.errors.google_no_refresh_token') if tokens['refresh_token'].blank?

      save(REFRESH_TOKEN, tokens['refresh_token'])
      save(EMAIL, userinfo(tokens['access_token'])['email'])
    end

    def disconnect!
      InstallationConfig.where(name: [REFRESH_TOKEN, EMAIL]).destroy_all
      GlobalConfig.clear_cache
    end

    # A short-lived access token, cached for most of its hour.
    def access_token
      raise Error, I18n.t('agenda.errors.google_not_connected') unless connected?

      Rails.cache.fetch(['agenda', 'google', 'access_token', Digest::SHA256.hexdigest(refresh_token)], expires_in: ACCESS_TOKEN_TTL) do
        token_request(grant_type: 'refresh_token', refresh_token: refresh_token)['access_token']
      end
    end

    private

    def token_request(params)
      response = HTTParty.post(TOKEN_URL, body: params.merge(client_id: client_id, client_secret: client_secret), timeout: HTTP_TIMEOUT)
      raise Error, I18n.t('agenda.errors.google_expired') if response.code == 400 && response.parsed_response.try(:[], 'error') == 'invalid_grant'
      raise Error, I18n.t('agenda.errors.google_status', status: response.code) unless response.success?

      response.parsed_response
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError
      raise Error, I18n.t('agenda.errors.unreachable')
    end

    def userinfo(access_token)
      HTTParty.get(USERINFO_URL, headers: { 'Authorization' => "Bearer #{access_token}" }, timeout: HTTP_TIMEOUT).parsed_response.to_h
    end

    def save(name, value)
      InstallationConfig.find_or_initialize_by(name: name).update!(value: value.to_s, locked: false)
    end

    def refresh_token
      InstallationConfig.find_by(name: REFRESH_TOKEN)&.value.presence
    end

    def client_id
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    end

    def client_secret
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil)
    end
  end
end
