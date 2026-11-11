# Stripe telling us a sale was paid, or a card was saved for the token charges,
# and — for the recurring card — when a monthly charge fails or is paid.
#
# This is the only place that learns about a payment on its own. Without it, a
# customer who pays and closes the tab before the redirect would have the money
# taken and nothing recorded here.
class Webhooks::Commercial::StripeController < ActionController::API
  HANDLED_EVENTS = %w[checkout.session.completed invoice.payment_failed invoice.paid].freeze

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
    return handle_invoice(event['type'], event['data']['object']) if event['type'].start_with?('invoice.')

    session = event['data']['object']
    # `session` is a `Stripe::Checkout::Session` (a `Stripe::StripeObject`) —
    # it supports `[]` and method access but does NOT implement `dig`, so a
    # `session.dig('metadata', 'sales_quote_id')` here raised `NoMethodError`
    # and returned 500 to Stripe. Bracket-access it directly.
    metadata = session['metadata']
    quote = SalesQuote.find_by(id: metadata && metadata['sales_quote_id'])
    return if quote.blank?

    session['mode'] == 'setup' ? record_token_card(quote, session) : record_payment(quote, session)
  end

  # Stripe retries until we answer, so the same payment arrives more than once.
  def record_payment(quote, session)
    return if quote.converted?

    schedule_renewal(quote, session) if quote.payment_method_card_recurring?
    quote.update!(status: :paid)
    quote.events.create!(event: 'payment_confirmed', metadata: { session_id: session['id'] })
    Sales::ConvertQuoteService.new(quote: quote).perform
    Sales::ClickupCrmSyncJob.perform_later(quote.id, 'paid_fields')
  end

  # The recurring card renews at another price; the schedule that plans it is
  # set up off the request, so a Stripe hiccup there never holds the sale.
  def schedule_renewal(quote, session)
    quote.update!(stripe_subscription_id: session['subscription'])
    Sales::CardRecurringScheduleJob.perform_later(quote.id)
  end

  # Only the recurring card follows its invoices: a failed charge starts the
  # count to the suspension (Sales::OverdueSuspensionJob), and a paid one stops
  # it and brings back an account that was suspended for it.
  def handle_invoice(type, invoice)
    quote = SalesQuote.payment_method_card_recurring.find_by(stripe_subscription_id: invoice_subscription_id(invoice))
    return if quote.nil?

    type == 'invoice.paid' ? record_invoice_paid(quote, invoice) : record_invoice_failed(quote, invoice)
  end

  # Moved under `parent.subscription_details` in the 2025-03-31 API; older
  # endpoint versions still send it at the top level.
  def invoice_subscription_id(invoice)
    return invoice['subscription'] if invoice['subscription'].present?

    parent = invoice['parent']
    parent && parent['subscription_details'] && parent['subscription_details']['subscription']
  end

  def record_invoice_failed(quote, invoice)
    return if quote.payment_overdue_since.present?

    quote.update!(payment_overdue_since: Time.zone.at(invoice['created']))
    quote.events.create!(event: 'payment_failed', metadata: { invoice_id: invoice['id'] })
  end

  def record_invoice_paid(quote, invoice)
    return if quote.payment_overdue_since.blank?

    quote.update!(payment_overdue_since: nil)
    quote.events.create!(event: 'overdue_payment_received', metadata: { invoice_id: invoice['id'] })
    reactivate_account(quote)
  end

  # Only an account this flow suspended comes back; one suspended by the team
  # for another reason stays as it is.
  def reactivate_account(quote)
    return unless quote.account&.suspended?

    last = quote.events.where(event: %w[account_suspended account_reactivated]).order(:created_at).last
    return unless last&.event == 'account_suspended'

    quote.account.active!
    quote.events.create!(event: 'account_reactivated', metadata: { account_id: quote.account_id })
  end

  def record_token_card(quote, session)
    quote.update!(token_payment_method_id: session['setup_intent'])
    quote.events.create!(event: 'token_card_saved', metadata: { session_id: session['id'] })
    Sales::ClickupCrmSyncJob.perform_later(quote.id, 'closed')
  end
end
