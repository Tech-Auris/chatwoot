# Thin HTTP wrapper around the AsaaS REST API, which is where a long plan paid
# in instalments is charged — Stripe carries the monthly subscription, and PIX
# à-vista comes in through Banco Inter. AsaaS covers both card in instalments
# and the boleto book (carnê) — same installment endpoint, `billingType` picks
# which.
#
# The endpoints exposed here mirror what the sales flow needs: cadastre the
# prospect as an AsaaS customer, open an instalment charge locked at the plan's
# N (6 for semiannual, 12 for annual), and pull the invoice URL of the first
# instalment so the customer can pay right away.
class Integrations::Asaas::Client
  PRODUCTION_URL = 'https://api.asaas.com/v3'.freeze
  SANDBOX_URL = 'https://api-sandbox.asaas.com/v3'.freeze
  DEFAULT_TIMEOUT = 15

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

  # Finds the AsaaS customer whose document matches — used to keep the flow
  # idempotent. AsaaS returns 200 with `{ data: [...] }` even when nothing
  # matched, so an empty `data` means "no customer with that document".
  def find_customer(cpf_cnpj:)
    digits = cpf_cnpj.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    body = get_json('/customers', cpfCnpj: digits)
    Array(body.is_a?(Hash) ? body['data'] : nil).first
  end

  # Cadastres the prospect on AsaaS so their instalments can hang off it.
  # Notifications are off: the sales team is the one talking to the prospect,
  # and AsaaS's own e-mail template does not match our tone.
  def create_customer(name:, email:, cpf_cnpj:, phone: nil)
    post_json('/customers', {
      name: name,
      email: email,
      cpfCnpj: cpf_cnpj.to_s.gsub(/\D/, ''),
      phone: phone.presence,
      mobilePhone: phone.presence,
      notificationDisabled: true
    }.compact)
  end

  # Opens an instalment charge with the number of parcels locked at N —
  # AsaaS creates N `payments` under the returned `installment.id`, each with
  # its own due date and its own invoice URL. Card + boleto share the shape;
  # for boleto this is a carnê, for card a single card auth split into N.
  # Amounts here are in reais, unlike Stripe, which counts cents.
  def create_installment(customer_id:, billing_type:, total_value_cents:, installment_count:, due_date:, description: nil) # rubocop:disable Metrics/ParameterLists
    post_json('/installments', {
      customer: customer_id,
      billingType: billing_type,
      installmentCount: installment_count.to_i,
      totalValue: (total_value_cents.to_i / 100.0).round(2),
      dueDate: due_date.to_date.iso8601,
      description: description.presence
    }.compact)
  end

  # Lists the payments AsaaS created under an instalment charge, ordered by
  # due date. The first one's `invoiceUrl` is what the customer opens right
  # after signing — the AsaaS-hosted page that shows the first boleto (with
  # every following one attached) or the card checkout for the whole book.
  def list_installment_payments(installment_id)
    body = get_json("/installments/#{installment_id}/payments")
    Array(body.is_a?(Hash) ? body['data'] : nil)
  end

  # An instalment charge of a sale that changed its mind is a book of boletos
  # with nowhere to land, so it is taken down rather than left open. AsaaS
  # cancels the parent and every child payment in one call.
  def delete_installment(installment_id)
    response = HTTParty.delete(
      "#{base_url}/installments/#{installment_id}",
      headers: default_headers,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  private

  def get_json(path, query = {})
    response = HTTParty.get(
      "#{base_url}#{path}",
      headers: default_headers,
      query: query.compact,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

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
