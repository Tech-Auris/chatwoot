# Takes the proposal from "confirmed" to "paid", recording the signature on the
# way.
#
# The terms are signed before any money moves. If the payment fails, the
# customer has agreed to terms they were shown and did not pay — recoverable.
# The reverse, money taken against a signature that was never recorded, is not.
class Sales::CheckoutService
  # How long each plan covers. A sale is never split into more instalments than
  # the months it pays for.
  CYCLE_MONTHS = { monthly: 1, semiannual: 6, annual: 12 }.freeze
  # PIX is paid outside Stripe, so the discount is ours to grant.
  PIX_DISCOUNT_PERCENT = { semiannual: 5, annual: 10 }.freeze
  # How long the monthly plan is contracted for. Stripe has no notion of a
  # minimum term, so it rides on the subscription as metadata and is stated on
  # the page — what holds it is the contract the customer signs.
  MINIMUM_TERM_MONTHS = 12

  Result = Struct.new(:quote, :checkout_url, :awaiting_manual_payment, keyword_init: true)

  class TermsNotAccepted < StandardError; end
  class UnsupportedPaymentMethod < StandardError; end

  def initialize(quote:, payment_method:, urls: {}, request: nil, client: nil)
    @quote = quote
    @payment_method = payment_method.to_s
    @urls = urls
    @request = request
    @client = client
  end

  # The signature is recorded by the caller, which is the only place that knows
  # the address and the browser it came from. This refuses to move money until
  # that record exists.
  def perform
    raise TermsNotAccepted, 'É preciso aceitar os termos de uso' unless terms_signed?

    raise UnsupportedPaymentMethod, 'O plano mensal é pago no cartão' unless self.class.offers?(payment_method, quote.billing_cycle)

    quote.update!(payment_method: payment_method)

    return await_manual_payment if payment_method == 'pix'

    return start_asaas_checkout if self.class.card_provider_for(quote.billing_cycle) == :asaas

    start_card_checkout
  end

  # What the customer pays every month once the first invoice is settled: the
  # recurring lines, discounted. The one-off ones — the setup fee — are charged
  # with that first invoice and never again.
  def self.monthly_charge_for(quote)
    new(quote: quote, payment_method: 'card').monthly_charge
  end

  def monthly_charge
    return 0 unless quote.billing_cycle_monthly?

    discounted_lines.select { |line| line[:recurring] }.sum { |line| line[:amount] }
  end

  # Who charges the card. The monthly plan is a subscription and belongs where
  # the recurrence lives; a semiannual or annual one is paid in instalments,
  # which is what the AsaaS link is for.
  def self.card_provider_for(billing_cycle)
    billing_cycle.to_s == 'monthly' ? :stripe : :asaas
  end

  # PIX is settled by hand against a period the customer already paid for, so
  # it is offered on the long plans only — a monthly one would mean chasing a
  # transfer every month.
  def self.offers?(payment_method, billing_cycle)
    return true if payment_method.to_s == 'card'

    payment_method.to_s == 'pix' && billing_cycle.to_s != 'monthly'
  end

  # What the customer saves by paying with PIX on a longer plan.
  def self.pix_discount_for(billing_cycle)
    PIX_DISCOUNT_PERCENT[billing_cycle&.to_sym] || 0
  end

  # What the AsaaS link offers, which is the configured cap held down to the
  # months the plan covers: twelve instalments on a semiannual plan would run
  # past the period being paid for.
  def self.max_installments_for(billing_cycle)
    months = CYCLE_MONTHS[billing_cycle&.to_sym].to_i
    return 1 if months <= 1

    [configured_max_installments, months].min
  end

  def self.configured_max_installments
    configured = GlobalConfig.get('ASAAS_MAX_INSTALLMENTS')['ASAAS_MAX_INSTALLMENTS'].to_i
    configured.positive? ? configured : Integrations::Asaas::Client::DEFAULT_MAX_INSTALLMENTS
  end

  private

  attr_reader :quote, :payment_method, :urls, :request

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def terms_signed?
    quote.terms_acceptances.status_signed.any?
  end

  def await_manual_payment
    quote.update!(status: :signed)
    quote.events.create!(event: 'awaiting_pix_payment', metadata: { total: quote.total_amount })

    Result.new(quote: quote, awaiting_manual_payment: true)
  end

  # The card in instalments, charged by AsaaS. The link is generic — it carries
  # no customer — so the payment comes back to us through the same manual
  # confirmation a PIX does.
  def start_asaas_checkout
    link = asaas_client.create_payment_link(
      name: "AurisChat — #{quote.prospect_name}",
      description: quote.discount_summary.presence,
      value_cents: quote.total_amount,
      max_installment_count: self.class.max_installments_for(quote.billing_cycle)
    )

    quote.update!(status: :signed, asaas_payment_link_id: link['id'], asaas_payment_link_url: link['url'])
    quote.events.create!(event: 'asaas_link_created', metadata: { link_id: link['id'], url: link['url'] })

    Result.new(quote: quote, checkout_url: link['url'], awaiting_manual_payment: false)
  end

  def asaas_client
    @asaas_client ||= Integrations::Asaas::Client.new
  end

  def start_card_checkout
    session = client.create_checkout_session(
      customer_id: customer_id,
      line_items: line_items,
      urls: urls,
      max_installments: self.class.max_installments_for(quote.billing_cycle),
      metadata: { sales_quote_id: quote.id },
      **subscription_payload
    )
    quote.update!(status: :signed, stripe_customer_id: customer_id)
    quote.events.create!(event: 'checkout_started', metadata: { session_id: session.id })

    Result.new(quote: quote, checkout_url: session.url, awaiting_manual_payment: false)
  end

  # Only the monthly plan is a subscription; a long plan reaching Stripe is a
  # single charge, and today it does not reach Stripe at all.
  def subscription_payload
    return {} unless quote.billing_cycle_monthly?

    { mode: 'subscription',
      subscription_data: { metadata: { sales_quote_id: quote.id, minimum_term_months: MINIMUM_TERM_MONTHS } } }
  end

  # The customer exists in Stripe from here on: the subscription, the invoices
  # and the token charges all hang off it.
  def customer_id
    @customer_id ||= Sales::StripeCustomerService.new(quote: quote, client: client).ensure!
  end

  # A long plan is one charge of the agreed total. The monthly one is billed
  # line by line, because what recurs and what is charged once have to part
  # ways: the subscription carries the plan, and the setup fee rides on the
  # first invoice only.
  def line_items
    return single_line_items unless quote.billing_cycle_monthly?
    # A proposal with no lines of its own still has a total, and on a monthly
    # plan that total is what recurs.
    return [checkout_line(name: "AurisChat — #{quote.prospect_name}", recurring: true, amount: quote.total_amount)] if quote.items.empty?

    discounted_lines.map { |line| checkout_line(**line) }
  end

  def single_line_items
    [{
      quantity: 1,
      price_data: {
        currency: quote.currency,
        unit_amount: quote.total_amount,
        product_data: { name: "AurisChat — #{quote.prospect_name}", description: quote.discount_summary.presence }.compact
      }
    }]
  end

  def checkout_line(name:, amount:, recurring:)
    price_data = { currency: quote.currency, unit_amount: amount, product_data: { name: name } }
    price_data[:recurring] = { interval: 'month' } if recurring

    { quantity: 1, price_data: price_data }
  end

  # The discount was agreed on the proposal as a whole and holds for as long as
  # the plan runs, so it is spread across the lines and baked into the amounts
  # rather than handed to Stripe as a coupon — one arithmetic, ours, and no
  # drift between what the customer read and what the invoice says.
  #
  # The rounding residue lands on the largest line, so the first invoice adds up
  # to the agreed total to the cent.
  def discounted_lines
    @discounted_lines ||= begin
      lines = quote.items.map { |item| { name: line_name(item), recurring: item.recurring_interval.present?, amount: discounted(item) } }
      apply_residue(lines)
    end
  end

  def discounted(item)
    return item.total_amount if quote.subtotal_amount.to_i.zero?

    (item.total_amount * (quote.subtotal_amount - quote.discount_amount) / quote.subtotal_amount.to_f).round
  end

  def apply_residue(lines)
    residue = quote.total_amount - lines.sum { |line| line[:amount] }
    return lines if residue.zero? || lines.empty?

    lines.max_by { |line| line[:amount] }[:amount] += residue
    lines
  end

  def line_name(item)
    item.quantity > 1 ? "#{item.name} (#{item.quantity}×)" : item.name
  end
end
