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
  # Buffer between signing and the first AsaaS instalment falling due, so the
  # customer has time to open the link and pay the first boleto.
  FIRST_DUE_DATE_DAYS = 3

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

    discard_open_asaas_installment
    quote.update!(payment_method: payment_method)

    return await_manual_payment if payment_method == 'pix'
    return start_asaas_checkout(billing_type: 'BOLETO') if payment_method == 'boleto'

    return start_asaas_checkout(billing_type: 'CREDIT_CARD') if self.class.card_provider_for(quote.billing_cycle) == :asaas

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

  # PIX and boleto are settled by hand against a period the customer already
  # paid for, so both are offered on the long plans only — a monthly one would
  # mean chasing a transfer every month, or reissuing a boleto every month.
  def self.offers?(payment_method, billing_cycle)
    return true if payment_method.to_s == 'card'

    %w[pix boleto].include?(payment_method.to_s) && billing_cycle.to_s != 'monthly'
  end

  # What the customer saves by paying with PIX on a longer plan.
  def self.pix_discount_for(billing_cycle)
    PIX_DISCOUNT_PERCENT[billing_cycle&.to_sym] || 0
  end

  # How many parcels the AsaaS charge is split into for this plan — locked, not
  # a cap. Semiannual pays in six, annual in twelve; the monthly plan is a
  # Stripe subscription and never reaches AsaaS at all. The number the CRM
  # reads on `Forma de Pagamento` mirrors this.
  def self.installments_for(billing_cycle)
    CYCLE_MONTHS[billing_cycle&.to_sym].to_i.clamp(1, 12)
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
    Sales::InterPixCobService.new(quote: quote).ensure_cob!

    Result.new(quote: quote, awaiting_manual_payment: true)
  end

  # A customer who comes back to change how they pay leaves an open instalment
  # behind. Cancelling it keeps exactly one live book per proposal — a payment
  # on the old one would arrive against terms nobody is holding.
  def discard_open_asaas_installment
    return if quote.asaas_installment_id.blank?

    asaas_client.delete_installment(quote.asaas_installment_id)
    quote.update!(asaas_installment_id: nil, asaas_invoice_url: nil)
  rescue Integrations::Asaas::Client::Error => e
    # An instalment we could not take down must not stop the customer from
    # paying with the new method.
    Rails.logger.info("[sales] asaas installment #{quote.asaas_installment_id} not removed: #{e.message}")
  end

  # The long plan charged by AsaaS: a card auth split into N or a book of N
  # boletos, with N locked to the plan's months (6 for semiannual, 12 for
  # annual). The customer is registered as an AsaaS customer up-front so the
  # instalment book hangs off a real identity — that is what lets AsaaS
  # notify the finance team and reconcile per instalment down the line.
  def start_asaas_checkout(billing_type:) # rubocop:disable Metrics/AbcSize
    customer_id = ensure_asaas_customer_id
    installment = asaas_client.create_installment(
      customer_id: customer_id,
      billing_type: billing_type,
      total_value_cents: quote.total_amount,
      installment_count: self.class.installments_for(quote.billing_cycle),
      due_date: Time.zone.today + FIRST_DUE_DATE_DAYS,
      description: asaas_description
    )

    invoice_url = first_invoice_url_for(installment['id'])
    quote.update!(status: :signed, asaas_customer_id: customer_id,
                  asaas_installment_id: installment['id'], asaas_invoice_url: invoice_url)
    quote.events.create!(event: 'asaas_installment_created',
                         metadata: { installment_id: installment['id'], invoice_url: invoice_url,
                                     billing_type: billing_type,
                                     installment_count: self.class.installments_for(quote.billing_cycle) })

    Result.new(quote: quote, checkout_url: invoice_url, awaiting_manual_payment: false)
  end

  # The prospect's e-mail is used to look up the AsaaS customer that may
  # already be there from a previous try — otherwise a new one is created.
  # Idempotent so a retried checkout does not spawn a second customer for the
  # same document.
  def ensure_asaas_customer_id
    return quote.asaas_customer_id if quote.asaas_customer_id.present?

    document = quote.company_document.presence || quote.prospect_document
    existing = asaas_client.find_customer(cpf_cnpj: document)
    return existing['id'] if existing.is_a?(Hash) && existing['id'].present?

    asaas_client.create_customer(name: asaas_billing_name, email: quote.prospect_email,
                                 cpf_cnpj: document, phone: quote.prospect_phone)['id']
  end

  # The billing name goes onto AsaaS the same way it goes onto Stripe — the
  # invoice is issued against the company when the customer asked for it, and
  # against the person otherwise.
  def asaas_billing_name
    quote.billing_name.presence || quote.company_name.presence || quote.prospect_name
  end

  # AsaaS hosts the payment page for the first boleto (or the card checkout
  # for the full card auth). The URL is per-payment, so we grab it from the
  # first payment under the instalment right after creation — that is the one
  # the customer opens now.
  def first_invoice_url_for(installment_id)
    payments = asaas_client.list_installment_payments(installment_id)
    first = payments.min_by { |payment| payment['dueDate'].to_s }
    first && first['invoiceUrl']
  end

  # AsaaS shows this on the payment page and on the boleto description. The
  # discount summary the seller wrote already reads well for the customer, so
  # it doubles as the sentence here when present.
  def asaas_description
    ["AurisChat — #{quote.prospect_name}", quote.discount_summary.presence].compact.join(' · ')
  end

  def asaas_client
    @asaas_client ||= Integrations::Asaas::Client.new
  end

  def start_card_checkout
    session = client.create_checkout_session(
      customer_id: customer_id,
      line_items: line_items,
      urls: urls,
      max_installments: self.class.installments_for(quote.billing_cycle),
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

    # No minimum term: the subscription renews month to month until the
    # customer cancels.
    { mode: 'subscription', subscription_data: { metadata: { sales_quote_id: quote.id } } }
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
