# Takes the proposal from "confirmed" to "paid", recording the signature on the
# way.
#
# The terms are signed before any money moves. If the payment fails, the
# customer has agreed to terms they were shown and did not pay — recoverable.
# The reverse, money taken against a signature that was never recorded, is not.
class Sales::CheckoutService
  # Brazilian installment caps by plan length.
  MAX_INSTALLMENTS = { semiannual: 6, annual: 12 }.freeze
  # PIX is paid outside Stripe, so the discount is ours to grant.
  PIX_DISCOUNT_PERCENT = { semiannual: 5, annual: 10 }.freeze

  Result = Struct.new(:quote, :checkout_url, :awaiting_manual_payment, keyword_init: true)

  class TermsNotAccepted < StandardError; end

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

    quote.update!(payment_method: payment_method)

    payment_method == 'pix' ? await_manual_payment : start_card_checkout
  end

  # What the customer saves by paying with PIX on a longer plan.
  def self.pix_discount_for(billing_cycle)
    PIX_DISCOUNT_PERCENT[billing_cycle&.to_sym] || 0
  end

  def self.max_installments_for(billing_cycle)
    MAX_INSTALLMENTS[billing_cycle&.to_sym] || 1
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

  def start_card_checkout
    session = client.create_checkout_session(
      customer_id: customer_id,
      line_items: line_items,
      urls: urls,
      max_installments: self.class.max_installments_for(quote.billing_cycle),
      metadata: { sales_quote_id: quote.id }
    )
    quote.update!(status: :signed, stripe_customer_id: customer_id)
    quote.events.create!(event: 'checkout_started', metadata: { session_id: session.id })

    Result.new(quote: quote, checkout_url: session.url, awaiting_manual_payment: false)
  end

  # The customer exists in Stripe from here on: the subscription, the invoices
  # and the token charges all hang off it.
  #
  # Everything the prospect already typed on our form is pushed onto it, so the
  # payment page opens filled in instead of asking for the same data twice.
  def customer_id
    @customer_id ||= begin
      id = quote.stripe_customer_id.presence || client.create_customer(name: billing_name, email: quote.prospect_email).id
      client.update_customer(id, name: billing_name, email: quote.prospect_email, phone: quote.prospect_phone)
      attach_tax_id(id)
      id
    end
  end

  # The invoice is issued against the company when the customer asked for it,
  # and against the person otherwise.
  def billing_name
    quote.billing_name.presence || quote.company_name.presence || quote.prospect_name
  end

  # A CNPJ when there is one, the CPF otherwise. Stripe rejects a repeated tax
  # id, and a retried checkout would hit exactly that.
  def attach_tax_id(customer_id)
    document = quote.company_document.presence || quote.prospect_document
    digits = document.to_s.gsub(/\D/, '')
    return if digits.blank?

    type = digits.length > 11 ? 'br_cnpj' : 'br_cpf'
    return if client.list_tax_ids(customer_id).data.any? { |tax_id| tax_id.value.to_s.gsub(/\D/, '') == digits }

    client.create_tax_id(customer_id, type: type, value: document)
  rescue Integrations::Stripe::Client::InvalidRequest => e
    # A document Stripe refuses must not stop the sale; the customer can type it
    # on the payment page.
    Rails.logger.info("[sales] tax id not attached to #{customer_id}: #{e.message}")
  end

  # A single line with the agreed total. The breakdown lives on the proposal;
  # sending the catalogue prices here would ignore the discounts.
  def line_items
    [{
      quantity: 1,
      price_data: {
        currency: quote.currency,
        unit_amount: quote.total_amount,
        product_data: { name: "AurisChat — #{quote.prospect_name}", description: quote.discount_summary.presence }.compact
      }
    }]
  end
end
