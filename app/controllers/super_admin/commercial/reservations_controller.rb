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

    render json: { reservation: serialize(quote) }
  end

  # An AsaaS instalment sale that landed on the provider — the finance team
  # confirms it here so the proposal moves the same way a PIX sale does:
  # Stripe customer, out-of-band invoice, account created. Without this the
  # quote sits in `signed` forever, no matter that AsaaS already captured
  # the card.
  def register_asaas_payment
    quote = SalesQuote.find(params[:id])
    result = Sales::RegisterAsaasPaymentService.new(quote: quote).perform

    render json: { reservation: serialize(result.quote), account_name: result.account.name }, status: :created
  rescue Sales::RegisterAsaasPaymentService::InvalidTransition => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Integrations::Stripe::Client::Error => e
    render json: { error: "Stripe recusou: #{e.message}" }, status: :bad_gateway
  end

  def data
    quotes = Sales::ReservationSyncService.new(quotes: paginated_quotes.to_a).perform

    render json: {
      reservations: quotes.map { |quote| serialize(quote) },
      statuses: SalesQuote.distinct.pluck(:clickup_status).compact.sort,
      meta: pagination_meta
    }
  end

  private

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

  def serialize(quote)
    {
      id: quote.id,
      prospect_name: quote.company_name.presence || quote.prospect_name,
      contact_name: quote.prospect_name,
      seller_name: quote.seller&.name,
      clickup_status: quote.clickup_status,
      clickup_url: "https://app.clickup.com/t/#{quote.clickup_task_id}",
      status: quote.status,
      # A deal that closed on our side is what the team calls "ganho"; the rest
      # is still being worked.
      won: quote.converted?,
      reserved_until: quote.reserved_until,
      reservation_active: quote.reservation_active?,
      total_amount: quote.total_amount,
      token_card_saved: quote.token_payment_method_id.present?,
      token_card_waived: quote.token_card_waived_at.present?,
      # AsaaS instalment sales sit on `signed` until finance confirms the
      # capture landed on the provider. Surfaced so the reservations grid can
      # offer the "Registrar pagamento AsaaS" button on exactly those rows.
      awaiting_asaas_confirmation: awaiting_asaas_confirmation?(quote),
      public_url: sales_proposal_url(quote.public_token, host: ENV.fetch('FRONTEND_URL', request.base_url)),
      access_code: quote.access_code
    }
  end

  def awaiting_asaas_confirmation?(quote)
    quote.signed? && quote.payment_method_card? && quote.asaas_payment_link_id.present?
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
