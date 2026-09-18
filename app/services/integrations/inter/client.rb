# Thin HTTP wrapper around the Banco Inter API. Only the two endpoints the
# PIX flow needs are exposed:
#   * `oauth/v2/token` — client-credentials OAuth over mTLS, the auth Inter
#     requires on every request; the returned access token stays fresh for
#     ~1h and is memoised.
#   * `pix/v2/cob` — creates a dynamic PIX cob tied to an unique `txid`. The
#     `pixCopiaECola` in the response is the BR Code we show the customer.
#
# The webhook subscription (`PUT /webhook/{chave}`) is a one-off setup done
# from outside this class — a super_admin task or a rake, not part of the
# per-sale hot path.
#
# Inter's OAuth + API both require **mutual TLS**: the client cert + key are
# read from `InstallationConfig` (`INTER_CERT_PEM`, `INTER_KEY_PEM`). Without
# them `configured?` returns false and every call is a no-op — the sales
# flow falls back to the static PIX code.
class Integrations::Inter::Client
  BASE_URL = 'https://cdpj.partners.bancointer.com.br'.freeze
  DEFAULT_TIMEOUT = 15
  DEFAULT_COB_EXPIRATION_SECONDS = 3600

  class Error < StandardError; end
  class Unauthorized < Error; end
  class ProviderUnavailable < Error; end

  def initialize(client_id: nil, client_secret: nil, cert_pem: nil, key_pem: nil)
    @client_id = client_id.presence || GlobalConfig.get('INTER_CLIENT_ID')['INTER_CLIENT_ID']
    @client_secret = client_secret.presence || GlobalConfig.get('INTER_CLIENT_SECRET')['INTER_CLIENT_SECRET']
    @cert_pem = cert_pem.presence || GlobalConfig.get('INTER_CERT_PEM')['INTER_CERT_PEM']
    @key_pem = key_pem.presence || GlobalConfig.get('INTER_KEY_PEM')['INTER_KEY_PEM']
  end

  def configured?
    @client_id.present? && @client_secret.present? && @cert_pem.present? && @key_pem.present?
  end

  # Creates a dynamic PIX cob at the given txid — the same txid Inter will
  # send back on the webhook when the money lands, which is how the webhook
  # knows which sale to close. The value is the effective à-vista amount the
  # customer sees (already PIX-discounted).
  def create_cob(txid:, value_cents:, pix_key:, description:, debtor: nil, expiration_seconds: DEFAULT_COB_EXPIRATION_SECONDS) # rubocop:disable Metrics/ParameterLists
    body = {
      calendario: { expiracao: expiration_seconds.to_i },
      valor: { original: format('%.2f', value_cents.to_i / 100.0) },
      chave: pix_key,
      solicitacaoPagador: description.to_s.strip.presence
    }
    body[:devedor] = build_debtor(debtor) if debtor

    put_json("/pix/v2/cob/#{txid}", body.compact, scope: 'cob.write cob.read')
  end

  # Registers our webhook URL against the PIX key so Inter starts POSTing
  # events on it. Called from a one-off super_admin action or rake — not
  # every sale.
  def configure_webhook(pix_key:, webhook_url:)
    put_json("/webhook/#{pix_key}", { webhookUrl: webhook_url }, scope: 'webhook.write')
  end

  private

  # `devedor` in the Bacen PIX spec takes either `cpf` or `cnpj` plus `nome`.
  def build_debtor(debtor)
    digits = debtor[:document].to_s.gsub(/\D/, '')
    return nil if digits.blank?

    key = digits.length > 11 ? :cnpj : :cpf
    { key => digits, :nome => debtor[:name].to_s }
  end

  def put_json(path, body, scope:)
    token = access_token(scope: scope)
    response = HTTParty.put(
      "#{BASE_URL}#{path}",
      **mtls_options,
      body: body.to_json,
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  # OAuth tokens live ~1h; caching in-memory across a single sale is enough
  # for the common case (create-cob + one retry). A fresh token is fetched
  # on the next process, which is fine.
  def access_token(scope:)
    return @access_token if @access_token.present?

    response = HTTParty.post(
      "#{BASE_URL}/oauth/v2/token",
      **mtls_options,
      body: { grant_type: 'client_credentials', client_id: @client_id, client_secret: @client_secret, scope: scope },
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      timeout: DEFAULT_TIMEOUT
    )
    parsed = parse(response)
    @access_token = parsed['access_token'] || parsed[:access_token]
    raise Unauthorized, 'Inter did not answer with a token' if @access_token.blank?

    @access_token
  end

  # Inter's OAuth + PIX endpoints both require mutual TLS. HTTParty takes the
  # cert + key inline on each call — a single Client instance is scoped to
  # one deploy's credentials, so this is safe to build every request.
  def mtls_options
    { pem: @cert_pem, key: @key_pem }
  end

  def parse(response)
    raise Unauthorized, 'Inter recusou a credencial' if [401, 403].include?(response.code)

    raise ProviderUnavailable, "Inter #{response.code}: #{error_message(response)}" unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  # Inter returns errors in Bacen's problem-details shape:
  # { "title": "...", "detail": "...", "type": "..." }.
  def error_message(response)
    body = response.parsed_response
    return response.body unless body.is_a?(Hash)

    [body['detail'], body['title']].compact.reject(&:empty?).first || response.body
  end
end
