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

  def paginated_quotes
    @paginated_quotes ||= begin
      scope = SalesQuote.includes(:seller, :items).order(created_at: :desc)
      scope = scope.where('LOWER(clickup_status) = ?', params[:clickup_status].downcase) if params[:clickup_status].present?
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
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
      # Whether the prospect has confirmed name / clinic / phone / e-mail /
      # document on the public page — the step that unlocks contract and
      # payment. Reservations only needs it to surface progress inside the
      # `reserved` state; on later states the status alone already implies it.
      details_confirmed: quote.details_complete?,
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
