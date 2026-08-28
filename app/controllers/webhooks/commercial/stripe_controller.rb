# Stripe telling us a sale was paid, or a card was saved for the token charges.
#
# This is the only place that learns about a payment on its own. Without it, a
# customer who pays and closes the tab before the redirect would have the money
# taken and nothing recorded here.
class Webhooks::Commercial::StripeController < ActionController::API
  HANDLED_EVENTS = %w[checkout.session.completed].freeze

  def process_payload
    event = verified_event
    return head :bad_request if event.nil?

    handle(event) if HANDLED_EVENTS.include?(event['type'])

    head :ok
  end

  private

  # An unsigned payload is not from Stripe, and acting on it would let anyone
  # mark a sale as paid.
  def verified_event
    secret = GlobalConfig.get('STRIPE_WEBHOOK_SECRET')['STRIPE_WEBHOOK_SECRET']
    return nil if secret.blank?

    Stripe::Webhook.construct_event(request.body.read, request.headers['Stripe-Signature'], secret)
  rescue JSON::ParserError, Stripe::SignatureVerificationError => e
    Rails.logger.warn("[commercial webhook] rejected: #{e.message}")
    nil
  end

  def handle(event)
    session = event['data']['object']
    quote = SalesQuote.find_by(id: session.dig('metadata', 'sales_quote_id'))
    return if quote.blank?

    session['mode'] == 'setup' ? record_token_card(quote, session) : record_payment(quote, session)
  end

  # Stripe retries until we answer, so the same payment arrives more than once.
  def record_payment(quote, session)
    return if quote.converted?

    quote.update!(status: :paid)
    quote.events.create!(event: 'payment_confirmed', metadata: { session_id: session['id'] })
    Sales::ConvertQuoteService.new(quote: quote).perform
  end

  def record_token_card(quote, session)
    quote.update!(token_payment_method_id: session['setup_intent'])
    quote.events.create!(event: 'token_card_saved', metadata: { session_id: session['id'] })
  end
end
