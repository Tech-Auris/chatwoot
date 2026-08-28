# The first PIX payment of a sale: the money came in through Inter or AsaaS,
# and from here the proposal becomes an account.
#
# The invoice is created and written off in the same breath so Stripe carries
# the sale too — the customer never sees a Stripe page, but the books read the
# same as a card sale.
class Sales::RegisterPixPaymentService
  class InvalidTransition < StandardError; end

  Result = Struct.new(:quote, :account, :renewal, keyword_init: true)

  def initialize(quote:, paid_via:, client: nil)
    @quote = quote
    @paid_via = paid_via
    @client = client
  end

  def perform
    raise InvalidTransition, 'Esta proposta não é de pagamento por PIX' unless quote.payment_method_pix?
    raise InvalidTransition, 'Esta proposta já foi paga' if quote.account_id.present?

    settle_in_stripe
    quote.update!(status: :paid)
    quote.events.create!(event: 'pix_payment_registered', metadata: { paid_via: paid_via, total: quote.total_amount })

    account = Sales::ConvertQuoteService.new(quote: quote).perform.account
    Result.new(quote: quote.reload, account: account, renewal: open_first_renewal(account))
  end

  private

  attr_reader :quote, :paid_via

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def settle_in_stripe
    customer_id = Sales::StripeCustomerService.new(quote: quote, client: client).ensure!
    quote.update!(stripe_customer_id: customer_id)

    invoice = client.create_invoice(
      customer_id: customer_id,
      items: [{ description: "AurisChat — #{quote.prospect_name}", unit_amount: quote.total_amount, quantity: 1 }],
      days_until_due: 1,
      description: quote.discount_summary.presence,
      metadata: { sales_quote_id: quote.id }
    )
    client.pay_invoice_out_of_band(invoice.id, paid_via: paid_via)
    quote.update!(stripe_invoice_id: invoice.id)
  end

  # The cycle just paid runs from today, so the next one is due a cycle ahead.
  def open_first_renewal(account)
    Sales::PixRenewalService.open_period(quote: quote, account: account, from: Date.current)
  end
end
