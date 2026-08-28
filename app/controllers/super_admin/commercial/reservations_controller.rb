# Where the sales team follows the proposals it has out: who reserved, until
# when, where the deal stands and the link to send again.
#
# The status and the deadline are mirrored from ClickUp on every load — that is
# where the team moves the deal, and a report showing a stale column would send
# somebody chasing a customer who already closed.
class SuperAdmin::Commercial::ReservationsController < SuperAdmin::ApplicationController
  PER_PAGE = 25
  DEFAULT_STATUS = 'negociação'.freeze

  def index; end

  def data
    quotes = Sales::ReservationSyncService.new(quotes: paginated_quotes.to_a).perform

    render json: {
      reservations: quotes.map { |quote| serialize(quote) },
      statuses: SalesQuote.distinct.pluck(:clickup_status).compact.sort,
      meta: pagination_meta
    }
  end

  private

  def paginated_quotes
    @paginated_quotes ||= begin
      scope = SalesQuote.includes(:seller, :items).order(created_at: :desc)
      scope = scope.where('LOWER(clickup_status) = ?', clickup_status_filter.downcase) if clickup_status_filter.present?
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
  end

  # The screen opens on the deals still being negotiated, which is the list the
  # team actually works; asking for every status is an explicit choice, sent as
  # an empty filter.
  def clickup_status_filter
    params.key?(:clickup_status) ? params[:clickup_status] : DEFAULT_STATUS
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
      public_url: sales_proposal_url(quote.public_token, host: ENV.fetch('FRONTEND_URL', request.base_url)),
      access_code: quote.access_code
    }
  end

  def pagination_meta
    {
      current_page: paginated_quotes.current_page,
      total_pages: paginated_quotes.total_pages,
      total_count: paginated_quotes.total_count,
      default_status: DEFAULT_STATUS,
      applied_status: clickup_status_filter
    }
  end
end
