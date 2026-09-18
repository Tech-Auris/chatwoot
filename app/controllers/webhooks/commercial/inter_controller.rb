# Inter telling us a PIX matched one of our dynamic cobs. Every proposal
# whose customer picks PIX has a `txid` we opened on Inter at signature; the
# webhook lands with that same `txid` and we route to the same conversion
# flow the manual "Registrar pagamento PIX" button runs.
#
# Signature: Inter mandates mutual TLS on the webhook — production is
# expected to terminate that at the reverse proxy (nginx / Cloudflare)
# ahead of Rails. On top of that we keep a shared secret in the URL path
# (`INTER_WEBHOOK_TOKEN`) so a leaked URL alone cannot mark a sale as paid.
# `txid` itself is only ever known to Inter (issued via mTLS) and to us
# (stored on the quote), which makes it a per-sale secret.
class Webhooks::Commercial::InterController < ActionController::API
  def process_payload
    return head :unauthorized unless authorized?

    parsed = JSON.parse(request.body.read)
    Array(parsed['pix']).each { |event| handle_pix_event(event) }

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  # Path token is compared with SecurityUtils to keep the check timing-safe.
  # A blank configured token refuses every request — fail-closed default.
  def authorized?
    expected = GlobalConfig.get('INTER_WEBHOOK_TOKEN')['INTER_WEBHOOK_TOKEN'].to_s
    return false if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected, params[:token].to_s)
  end

  # Each element under `pix` is one received PIX. A payment we cannot tie to
  # a known cob is dropped silently — Inter retries an unacknowledged webhook
  # otherwise, and raising here would flood the retry queue.
  def handle_pix_event(event)
    quote = SalesQuote.find_by(inter_txid: event['txid'])
    return if quote.blank?
    return unless quote.signed?

    quote.events.create!(event: 'inter_pix_received',
                         metadata: { txid: event['txid'], end_to_end_id: event['endToEndId'], value: event['valor'] })
    Sales::RegisterPixPaymentService.new(quote: quote, paid_via: 'inter').perform
  rescue Sales::RegisterPixPaymentService::InvalidTransition => e
    # A race between a duplicated webhook and the manual button lands here;
    # the sale is already settled and the ack is what Inter needs.
    Rails.logger.info("[inter webhook] convert skipped for #{quote.id}: #{e.message}")
  end
end
