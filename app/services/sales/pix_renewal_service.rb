# The two moves of a PIX billing period: issue the invoice, and settle it.
#
# Settling opens the next period, which is what keeps a PIX customer from
# quietly falling off the billing after one cycle.
class Sales::PixRenewalService
  class InvalidTransition < StandardError; end

  def initialize(renewal:, client: nil)
    @renewal = renewal
    @client = client
  end

  # Opens the period that comes after the given date, for the cycle the
  # proposal was sold on.
  def self.open_period(quote:, account:, from:)
    PixRenewal.create!(
      account: account,
      sales_quote: quote,
      due_on: from + PixRenewal.months_for(quote.billing_cycle).months,
      amount: quote.total_amount,
      status: :pending
    )
  end

  def issue_invoice!
    raise InvalidTransition, 'Esta renovação já foi faturada' unless renewal.status_pending?
    raise InvalidTransition, 'Conta sem cliente do Stripe vinculado' if customer_id.blank?

    invoice = client.create_invoice(
      customer_id: customer_id,
      items: [{ description: description, unit_amount: renewal.amount, quantity: 1 }],
      days_until_due: days_until_due,
      description: description,
      metadata: { pix_renewal_id: renewal.id }
    )
    renewal.update!(status: :invoiced, stripe_invoice_id: invoice.id, hosted_invoice_url: invoice.try(:hosted_invoice_url))
    renewal
  end

  # The money came in through Inter or AsaaS. Stripe is written off first so it
  # stays the record of what was billed and settled, and only then is the next
  # period opened.
  def register_payment!(paid_via:)
    raise InvalidTransition, 'Gere a fatura antes de dar baixa' unless renewal.status_invoiced?

    client.pay_invoice_out_of_band(renewal.stripe_invoice_id, paid_via: paid_via)
    renewal.update!(status: :paid, paid_via: paid_via, paid_at: Time.current)
    self.class.open_period(quote: renewal.sales_quote, account: renewal.account, from: renewal.due_on)

    renewal
  end

  # The customer left. The chain stops here — nothing opens the next period.
  def cancel!
    raise InvalidTransition, 'Uma renovação paga não pode ser cancelada' if renewal.status_paid?

    renewal.update!(status: :cancelled)
    renewal
  end

  private

  attr_reader :renewal

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def customer_id
    renewal.account.stripe_customer_id
  end

  def description
    "AurisChat — renovação #{renewal.due_on.strftime('%m/%Y')}"
  end

  # The invoice falls due on the day the period does. A period already past due
  # is billed for tomorrow, since Stripe counts days from today.
  def days_until_due
    [(renewal.due_on - Date.current).to_i, 1].max
  end
end
