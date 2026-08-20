# Invoices issued by Stripe, and the write-off for the ones paid elsewhere.
#
# Subscriptions here bill by invoice on purpose (see
# `Integrations::Stripe::Client#create_subscription`), because part of the
# customers pay by PIX at Banco Inter or through AsaaS. This screen is where
# that payment is registered against the invoice, keeping Stripe as the single
# record of what was billed and what was settled.
class SuperAdmin::Financial::InvoicesController < SuperAdmin::ApplicationController
  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  before_action :ensure_configured, except: [:index]

  def index; end

  def data
    list = client.list_invoices(status: params[:status], starting_after: params[:starting_after])
    load_account_names(list.data)

    render json: {
      invoices: list.data.map { |invoice| serialize(invoice) },
      meta: { has_more: list.has_more, last_id: list.data.last&.id, sources: Integrations::Stripe::Client::PAID_VIA_SOURCES }
    }
  end

  # Marks an invoice as settled outside Stripe, recording where the money came
  # in so the origin is auditable later.
  def pay
    invoice = client.pay_invoice_out_of_band(params[:id], paid_via: params[:paid_via])
    load_account_names([invoice])

    render json: { invoice: serialize(invoice) }
  end

  private

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  # Resolved for the whole page up front: a lookup inside the row loop would
  # either run a query per invoice or memoize on the first customer alone.
  def load_account_names(invoices)
    @account_names = Account.where(stripe_customer_id: invoices.filter_map(&:customer).uniq)
                            .pluck(:stripe_customer_id, :name).to_h
  end

  def serialize(invoice)
    {
      id: invoice.id,
      number: invoice.number,
      status: invoice.status,
      customer_id: invoice.customer,
      account_name: @account_names[invoice.customer],
      customer_name: invoice.customer_name,
      amount_due: invoice.amount_due,
      amount_paid: invoice.amount_paid,
      currency: invoice.currency,
      due_date: invoice.due_date,
      created: invoice.created,
      hosted_invoice_url: invoice.hosted_invoice_url,
      invoice_pdf: invoice.invoice_pdf,
      # Present only on invoices written off from this screen; invoices settled
      # inside Stripe (card, boleto) legitimately have no origin of ours.
      paid_via: invoice.metadata&.[](Integrations::Stripe::Client::PAID_VIA_METADATA_KEY)
    }
  end
end
