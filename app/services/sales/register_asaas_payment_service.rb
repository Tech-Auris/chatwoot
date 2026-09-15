# The first AsaaS card payment of a sale: the customer paid the instalment
# plan on the AsaaS link and the finance team confirmed it in the AsaaS
# dashboard. From here the proposal becomes an account.
#
# Runs the same conversion the PIX flow does — creates a Stripe customer,
# rides a one-off "paid out of band" invoice through Stripe so the books
# still read the whole sale, marks the quote paid and calls the account
# builder. Kept as a sibling of `RegisterPixPaymentService` (not a shared
# base) because the two flows will diverge as we grow around AsaaS
# (installment tracking, per-instalment reconciliation, refunds).
class Sales::RegisterAsaasPaymentService
  class InvalidTransition < StandardError; end

  Result = Struct.new(:quote, :account, keyword_init: true)

  def initialize(quote:, client: nil)
    @quote = quote
    @client = client
  end

  def perform # rubocop:disable Metrics/AbcSize
    raise InvalidTransition, 'Esta proposta não é de pagamento por cartão' unless quote.payment_method_card?
    raise InvalidTransition, 'Esta proposta já foi paga' if quote.account_id.present?
    # The link has to exist for AsaaS to have taken the payment; running this
    # on a proposal that never reached AsaaS would mean confirming a payment
    # that has no home in the provider.
    raise InvalidTransition, 'Esta proposta não passou pelo fluxo AsaaS' if quote.asaas_payment_link_id.blank?

    settle_in_stripe
    quote.update!(status: :paid)
    quote.events.create!(event: 'asaas_payment_registered',
                         metadata: { asaas_payment_link_id: quote.asaas_payment_link_id, total: quote.total_amount })

    account = Sales::ConvertQuoteService.new(quote: quote).perform.account
    Result.new(quote: quote.reload, account: account)
  end

  private

  attr_reader :quote

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  # The Stripe customer is the anchor for everything that hangs off the account
  # (token billing, later renewals, invoices). Even though AsaaS took the
  # money, Stripe carries the books — the invoice is created and paid
  # out-of-band in one call.
  def settle_in_stripe
    customer_id = Sales::StripeCustomerService.new(quote: quote, client: client).ensure!
    quote.update!(stripe_customer_id: customer_id)

    invoice = client.create_invoice(
      customer_id: customer_id,
      items: [{ description: "AurisChat — #{quote.prospect_name}", unit_amount: quote.total_amount, quantity: 1 }],
      days_until_due: 1,
      description: quote.discount_summary.presence,
      metadata: { sales_quote_id: quote.id, asaas_payment_link_id: quote.asaas_payment_link_id }
    )
    client.pay_invoice_out_of_band(invoice.id, paid_via: 'asaas')
    quote.update!(stripe_invoice_id: invoice.id)
  end
end
