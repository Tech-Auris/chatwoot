# The billing that does not renew itself.
#
# A card subscription is charged again by Stripe; PIX cannot back a recurring
# subscription, so every cycle of a PIX customer has to be billed by hand. This
# screen is the reminder — which periods are coming due, which are late, and
# which sales are still waiting for their first payment.
class SuperAdmin::Financial::PixRenewalsController < SuperAdmin::ApplicationController
  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  rescue_from Sales::PixRenewalService::InvalidTransition, Sales::RegisterPixPaymentService::InvalidTransition do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  before_action :ensure_configured, except: [:index]

  def index; end

  def data
    render json: {
      renewals: listed_renewals.map { |renewal| serialize(renewal) },
      awaiting_first_payment: awaiting_first_payment.map { |quote| serialize_quote(quote) },
      meta: {
        alert_count: PixRenewal.alerting.count,
        overdue_count: PixRenewal.overdue.count,
        alert_window_days: PixRenewal::ALERT_WINDOW_DAYS,
        sources: Integrations::Stripe::Client::PAID_VIA_SOURCES
      }
    }
  end

  def invoice
    renewal = service.issue_invoice!

    render json: { renewal: serialize(renewal) }
  end

  def pay
    renewal = service.register_payment!(paid_via: params[:paid_via])

    render json: { renewal: serialize(renewal) }
  end

  def cancel
    renewal = service.cancel!

    render json: { renewal: serialize(renewal) }
  end

  # The first PIX of a sale: settles it, creates the account and opens the
  # period that comes after.
  def register_sale
    quote = SalesQuote.find(params[:sales_quote_id])
    result = Sales::RegisterPixPaymentService.new(quote: quote, paid_via: params[:paid_via]).perform

    render json: { renewal: serialize(result.renewal), account_name: result.account.name }, status: :created
  end

  private

  def service
    @service ||= Sales::PixRenewalService.new(renewal: PixRenewal.find(params[:id]))
  end

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  # Open periods first and by due date, which is the order somebody works them
  # in; the settled ones are history and only show up when asked for.
  def listed_renewals
    scope = PixRenewal.includes(:account, :sales_quote)
    params[:status] == 'paid' ? scope.status_paid.order(paid_at: :desc) : scope.open_periods.order(:due_on)
  end

  # A sale settled outside Stripe stops at "signed" until somebody confirms the
  # money — a PIX at Banco Inter, or a card in instalments through the AsaaS
  # link. Nothing else in the product moves it, which is what this screen is for.
  def awaiting_first_payment
    SalesQuote.awaiting_manual_payment.order(:created_at)
  end

  def serialize(renewal)
    {
      id: renewal.id,
      account_name: renewal.account.name,
      customer_name: renewal.sales_quote.company_name.presence || renewal.sales_quote.prospect_name,
      reference_month: renewal.due_on.strftime('%m/%Y'),
      due_on: renewal.due_on,
      amount: renewal.amount,
      status: renewal.status,
      overdue: renewal.overdue?,
      alerting: renewal.status_pending? && renewal.due_on <= Date.current + PixRenewal::ALERT_WINDOW_DAYS,
      billing_cycle: renewal.sales_quote.billing_cycle,
      hosted_invoice_url: renewal.hosted_invoice_url,
      paid_via: renewal.paid_via,
      paid_at: renewal.paid_at
    }
  end

  def serialize_quote(quote)
    {
      id: quote.id,
      customer_name: quote.company_name.presence || quote.prospect_name,
      prospect_email: quote.prospect_email,
      amount: quote.total_amount,
      billing_cycle: quote.billing_cycle,
      payment_method: quote.payment_method,
      asaas_payment_link_url: quote.asaas_payment_link_url,
      signed_at: quote.terms_acceptances.status_signed.maximum(:signed_at)
    }
  end
end
