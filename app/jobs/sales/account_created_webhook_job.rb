# Calls the "Webhook de cadastro final" (Settings → Commercial) once a sale
# became an account, so an n8n flow sets up everything outside AurisChat. Signs
# the body with the configured secret in `X-Auris-Signature`
# (`sha256=<hex HMAC-SHA256>`). A non-2xx answer or a network error is retried
# with a growing wait; each outcome lands on the proposal's history.
class Sales::AccountCreatedWebhookJob < ApplicationJob
  queue_as :low

  URL_CONFIG = 'COMMERCIAL_ACCOUNT_WEBHOOK_URL'.freeze
  SECRET_CONFIG = 'COMMERCIAL_ACCOUNT_WEBHOOK_SECRET'.freeze
  TIMEOUT = 15

  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 8 do |job, error|
    quote = SalesQuote.find_by(id: job.arguments.first)
    quote&.events&.create!(event: 'account_webhook_failed', metadata: { error: error.message.truncate(500) })
  end

  def perform(quote_id)
    url = GlobalConfigService.load(URL_CONFIG, '').to_s.strip
    quote = SalesQuote.find_by(id: quote_id)
    return if url.blank? || quote&.account.blank?

    body = Sales::AccountCreatedPayload.new(quote: quote).to_h.to_json
    response = HTTParty.post(url, body: body, headers: headers(body), timeout: TIMEOUT)
    raise DeliveryError, "HTTP #{response.code}: #{response.body.to_s.truncate(300)}" unless response.success?

    quote.events.create!(event: 'account_webhook_sent', metadata: { account_id: quote.account_id, status: response.code })
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise DeliveryError, "#{e.class}: #{e.message}"
  end

  private

  def headers(body)
    headers = { 'Content-Type' => 'application/json', 'X-Auris-Event' => Sales::AccountCreatedPayload::EVENT }
    secret = GlobalConfigService.load(SECRET_CONFIG, '').to_s
    headers['X-Auris-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}" if secret.present?
    headers
  end
end
