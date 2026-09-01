# Thin HTTP wrapper around the AsaaS REST API, which is where a long plan paid
# by card in instalments is charged — Stripe carries the monthly subscription,
# and PIX comes in through Banco Inter.
#
# Only the payment link endpoint is exposed, which is all the sales flow needs:
# the customer opens the link, picks how many instalments, and the finance team
# confirms the money the same way it confirms a PIX.
class Integrations::Asaas::Client
  PRODUCTION_URL = 'https://api.asaas.com/v3'.freeze
  SANDBOX_URL = 'https://api-sandbox.asaas.com/v3'.freeze
  DEFAULT_TIMEOUT = 15
  DEFAULT_MAX_INSTALLMENTS = 12

  class Error < StandardError; end
  class Unauthorized < Error; end
  class ProviderUnavailable < Error; end

  def initialize(api_key: nil)
    @api_key = api_key.presence || GlobalConfig.get('ASAAS_API_KEY')['ASAAS_API_KEY']
  end

  def configured?
    @api_key.present?
  end

  # AsaaS issues a sandbox key and a production key for the same account, and
  # each answers on its own host. The key says which one it is, so there is no
  # second setting to keep in step with it.
  def sandbox?
    @api_key.to_s.include?('hmlg')
  end

  def base_url
    sandbox? ? SANDBOX_URL : PRODUCTION_URL
  end

  # A link the customer opens to pay by card in up to `max_installment_count`
  # instalments. Amounts here are in reais, unlike Stripe, which counts cents.
  #
  # Notifications are off: the prospect is not a registered AsaaS customer and
  # the sales team is the one talking to them.
  def create_payment_link(name:, value_cents:, max_installment_count: DEFAULT_MAX_INSTALLMENTS, description: nil)
    post_json('/paymentLinks', {
      billingType: 'CREDIT_CARD',
      chargeType: 'INSTALLMENT',
      name: name,
      description: description.presence,
      value: (value_cents.to_i / 100.0).round(2),
      maxInstallmentCount: max_installment_count.to_i,
      notificationEnabled: false
    }.compact)
  end

  # A link of a sale that changed its mind is money with nowhere to land, so it
  # is taken down rather than left open.
  def delete_payment_link(payment_link_id)
    response = HTTParty.delete(
      "#{base_url}/paymentLinks/#{payment_link_id}",
      headers: default_headers,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  private

  def post_json(path, body)
    response = HTTParty.post(
      "#{base_url}#{path}",
      headers: default_headers,
      body: body.to_json,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def default_headers
    { 'access_token' => @api_key.to_s, 'Content-Type' => 'application/json' }
  end

  def parse(response)
    raise Unauthorized, 'AsaaS recusou a credencial' if [401, 403].include?(response.code)

    raise ProviderUnavailable, "AsaaS #{response.code}: #{error_message(response)}" unless response.success?

    response.parsed_response
  end

  # AsaaS answers a refusal with { "errors": [{ "description": "..." }] }.
  def error_message(response)
    body = response.parsed_response
    return response.body unless body.is_a?(Hash)

    Array(body['errors']).filter_map { |error| error['description'] }.join(', ').presence || response.body
  end
end
