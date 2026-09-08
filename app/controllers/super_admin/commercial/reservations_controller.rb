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
      public_url: sales_proposal_url(quote.public_token, host: ENV.fetch('FRONTEND_URL', request.base_url)),
      access_code: quote.access_code
    }
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
