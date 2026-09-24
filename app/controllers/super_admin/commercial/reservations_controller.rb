# Where the sales team follows the proposals it has out: who reserved, until
# when, where the deal stands and the link to send again.
#
# The status and the deadline are mirrored from ClickUp on every load — that is
# where the team moves the deal, and a report showing a stale column would send
# somebody chasing a customer who already closed.
class SuperAdmin::Commercial::ReservationsController < SuperAdmin::ApplicationController
  PER_PAGE = 25

  def index; end

  # Some customers pay the year by PIX and have no card to leave on file. The
  # team says so here, and the usage is charged by invoice from then on — the
  # public page stops asking and moves the customer along.
  def waive_token_card
    quote = SalesQuote.find(params[:id])
    quote.update!(token_card_waived_at: Time.current)
    quote.events.create!(event: 'token_card_waived', metadata: { super_admin_id: current_super_admin.id })
    Sales::ClickupCrmSyncJob.perform_later(quote.id, 'closed')

    render json: { reservation: serialize(quote) }
  end

  # Boleto is off by default on every new proposal — the customer only
  # sees it as a payment option after the seller flips it on here. Same
  # shape as `waive_token_card`: stamped when enabled, kept as an event
  # for the audit trail.
  def enable_boleto
    quote = SalesQuote.find(params[:id])
    unless Sales::CheckoutService.offers?('boleto', quote.billing_cycle)
      return render(json: { error: 'boleto_unavailable_for_plan' }, status: :unprocessable_entity)
    end

    quote.update!(boleto_enabled_at: Time.current) if quote.boleto_enabled_at.blank?
    quote.events.create!(event: 'boleto_enabled', metadata: { super_admin_id: current_super_admin.id })

    render json: { reservation: serialize(quote) }
  end

  # A manual sale confirmation — the finance team clicks this when the money
  # landed on AsaaS (card / boleto) or Inter (PIX) and the webhook has not
  # closed the sale on its own. Routes to the right service based on the
  # quote's payment method; PIX also needs a `paid_via` (inter / asaas) to
  # know where the transfer came in.
  #
  # Kept `register_asaas_payment` as an alias below so any UI reading the
  # old route keeps working after the deploy — this endpoint is the one to
  # link to from now on.
  def register_payment
    quote = SalesQuote.find(params[:id])
    result = dispatch_registration(quote)

    render json: { reservation: serialize(result.quote), account_name: result.account.name }, status: :created
  rescue Sales::RegisterAsaasPaymentService::InvalidTransition,
         Sales::RegisterPixPaymentService::InvalidTransition => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Integrations::Stripe::Client::Error => e
    render json: { error: "Stripe recusou: #{e.message}" }, status: :bad_gateway
  end
  alias register_asaas_payment register_payment

  def data
    quotes = Sales::ReservationSyncService.new(quotes: paginated_quotes.to_a).perform

    render json: {
      reservations: quotes.map { |quote| serialize(quote) },
      statuses: SalesQuote.distinct.pluck(:clickup_status).compact.sort,
      meta: pagination_meta
    }
  end

  private

  # Picks the right service by the quote's payment method. PIX also carries
  # a `paid_via` because the money can come in through Inter (default) or
  # AsaaS — the finance team knows which and passes it on the request.
  def dispatch_registration(quote)
    if quote.payment_method_pix?
      Sales::RegisterPixPaymentService.new(quote: quote, paid_via: params.fetch(:paid_via, 'inter')).perform
    else
      Sales::RegisterAsaasPaymentService.new(quote: quote).perform
    end
  end

  # Statuses the pipeline treats as closed — the deal is either won or lost
  # and there is nothing left to work on. Hidden by default so the screen
  # opens on what is still moving; a checkbox brings them back for the full
  # history.
  FINALIZED_STATUSES = %w[ganho perdido].freeze

  def paginated_quotes
    @paginated_quotes ||= begin
      scope = SalesQuote.includes(:seller, :items).order(created_at: :desc)
      scope = scope.where('LOWER(clickup_status) = ?', params[:clickup_status].downcase) if params[:clickup_status].present?
      scope = filter_by_query(scope, params[:q]) if params[:q].present?
      scope = scope.where('clickup_status IS NULL OR LOWER(clickup_status) NOT IN (?)', FINALIZED_STATUSES) unless include_finalized?
      # "Reserva vencida" na UI cobre dois casos: `reserved_until` no
      # passado e `reserved_until` nulo (nunca reservada). O filtro casa a
      # mesma semântica — só linhas com deadline futura aparecem quando o
      # toggle está desligado.
      scope = scope.where('reserved_until >= ?', Time.current) unless include_expired?
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
  end

  # The seller can explicitly ask for closed deals with a checkbox on the
  # header; a status picker landing on `ganho`/`perdido` also implies it,
  # so a manual choice is not silently overridden.
  def include_finalized?
    ActiveModel::Type::Boolean.new.cast(params[:include_finalized]) ||
      FINALIZED_STATUSES.include?(params[:clickup_status].to_s.downcase)
  end

  # An expired reservation is a deal whose deadline already passed without a
  # signature; hidden by default and brought back by the header checkbox.
  def include_expired?
    ActiveModel::Type::Boolean.new.cast(params[:include_expired])
  end

  # Matches the same fields the Quotes autocomplete pretends to match on the
  # prospect card — name, clinic (company_name), e-mail, phone — so the
  # seller uses one gesture to find a deal in either screen. Phone is
  # matched on digits only so `(11) 91234-5678` and `11912345678` hit the
  # same row.
  def filter_by_query(scope, raw)
    q = raw.to_s.strip
    return scope if q.blank?

    like = "%#{q.downcase}%"
    digits = q.gsub(/\D/, '')
    digits_like = digits.present? ? "%#{digits}%" : nil

    scope.where(
      'LOWER(prospect_name) LIKE :like OR LOWER(company_name) LIKE :like OR ' \
      'LOWER(prospect_email) LIKE :like OR ' \
      '(:digits IS NOT NULL AND regexp_replace(coalesce(prospect_phone, \'\'), \'\\D\', \'\', \'g\') LIKE :digits)',
      like: like, digits: digits_like
    )
  end

  def serialize(quote) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    {
      id: quote.id,
      prospect_name: quote.company_name.presence || quote.prospect_name,
      contact_name: quote.prospect_name,
      prospect_phone: quote.prospect_phone,
      seller_name: quote.seller&.name,
      clickup_status: quote.clickup_status,
      clickup_url: "https://app.clickup.com/t/#{quote.clickup_task_id}",
      status: quote.status,
      # A deal that closed on our side is what the team calls "ganho"; the rest
      # is still being worked.
      won: quote.converted?,
      reserved_until: quote.reserved_until,
      reservation_active: quote.reservation_active?,
      total_amount: quote.effective_total_amount,
      token_card_saved: quote.token_payment_method_id.present?,
      token_card_waived: quote.token_card_waived_at.present?,
      boleto_available: quote.boleto_available?,
      boleto_enabled: quote.boleto_enabled_at.present?,
      boleto_eligible_for_plan: Sales::CheckoutService.offers?('boleto', quote.billing_cycle),
      payment_method: quote.payment_method,
      # A single flag the grid reads to show the "Registrar pagamento" button
      # for any sale still waiting on a manual confirmation — AsaaS card /
      # boleto and PIX, but not the monthly Stripe subscription (that one
      # closes on its own through the Stripe webhook).
      awaiting_manual_payment_confirmation: awaiting_manual_payment_confirmation?(quote),
      # Kept for the previous UI version until every client is on the new
      # bundle. Same meaning as before — only the AsaaS-side sales.
      awaiting_asaas_confirmation: awaiting_asaas_confirmation?(quote),
      register_payment_label: register_payment_label(quote),
      subtotal_amount: quote.subtotal_amount,
      discount_amount: quote.effective_discount_amount,
      discount_summary: quote.effective_discount_summary,
      items: quote.items.map { |item| serialize_item(item) },
      public_url: sales_proposal_url(quote.public_token, host: ENV.fetch('FRONTEND_URL', request.base_url)),
      access_code: quote.access_code,
      # Payment links generated during the sale — surfaced in the expanded
      # row so the sales team can resend the exact link the customer got.
      payment_links: payment_links(quote)
    }
  end

  # Handful of URLs we may have collected along the sale, per provider.
  # `nil` entries are dropped so the UI only paints what actually exists.
  def payment_links(quote)
    {
      asaas_payment_link: quote.asaas_payment_link_url.presence,
      asaas_invoice: quote.asaas_invoice_url.presence,
      # Stripe hosted invoice URL is not persisted; the dashboard link is
      # what the internal team needs to reconcile the sale.
      stripe_dashboard: quote.stripe_invoice_id.present? ? "https://dashboard.stripe.com/invoices/#{quote.stripe_invoice_id}" : nil,
      # Inter PIX has no public cobrança URL. Surfacing the txid is enough
      # for the finance team to look it up in the Inter panel.
      inter_pix_txid: quote.inter_txid.presence
    }.compact
  end

  # What the grid's expandable row needs to render the cart lines exactly
  # like the public proposal reads them.
  def serialize_item(item)
    {
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      total_amount: item.total_amount,
      recurring_interval: item.recurring_interval
    }
  end

  def awaiting_asaas_confirmation?(quote)
    quote.signed? && (quote.payment_method_card? || quote.payment_method_boleto?) && quote.asaas_installment_id.present?
  end

  # Every sale that lands on `signed` and never got its money confirmed by
  # a webhook or a manual click needs this button. Monthly Stripe cards are
  # excluded — Stripe closes the sale on its own.
  def awaiting_manual_payment_confirmation?(quote) # rubocop:disable Metrics/CyclomaticComplexity
    return false unless quote.signed?
    return false if quote.account_id.present?
    return false if quote.payment_method_card? && quote.billing_cycle_monthly?

    quote.payment_method_pix? ||
      ((quote.payment_method_card? || quote.payment_method_boleto?) && quote.asaas_installment_id.present?)
  end

  # Short human label the grid appends to the button so the operator sees
  # which flow will run before clicking: "PIX", "Cartão 12x", "Boleto 6x",
  # "Cartão". Nil when the row would not show the button.
  def register_payment_label(quote)
    return nil unless awaiting_manual_payment_confirmation?(quote)
    return 'PIX' if quote.payment_method_pix?
    return 'Cartão' if quote.payment_method_card? && quote.billing_cycle_monthly?

    n = Sales::CheckoutService.installments_for(quote.billing_cycle)
    return "Cartão #{n}x" if quote.payment_method_card?

    "Boleto #{n}x"
  end

  def pagination_meta
    {
      current_page: paginated_quotes.current_page,
      total_pages: paginated_quotes.total_pages,
      total_count: paginated_quotes.total_count,
      applied_status: params[:clickup_status].to_s
    }
  end
end
