# Audit of every successful login recorded by `LoginEventTrackingService`.
# Super Admin only — the customer's dashboard does not link here.
class SuperAdmin::LoginEventsController < SuperAdmin::ApplicationController
  PER_PAGE = 50

  def index
    @accounts = Account.order(:name).pluck(:id, :name)
  end

  def data
    render json: { events: paginated.map { |event| serialize(event) }, meta: pagination_meta }
  end

  private

  def paginated
    @paginated ||= filtered_scope.page(params[:page] || 1).per(PER_PAGE)
  end

  def filtered_scope
    scope = LoginEvent.includes(:user, :account)
                      .for_account(params[:account_id])
                      .for_role(params[:role])
                      .recent_first
    scope = scope.where('created_at >= ?', Time.zone.parse(params[:from])) if params[:from].present?
    scope = scope.where('created_at <= ?', Time.zone.parse(params[:to])) if params[:to].present?
    scope
  end

  def serialize(event)
    {
      id: event.id,
      created_at: event.created_at,
      user_id: event.user_id,
      user_name: event.user&.name,
      user_email: event.user&.email,
      account_id: event.account_id,
      account_name: event.account&.name,
      role: event.role,
      ip_address: event.ip_address,
      city: event.city,
      country: event.country,
      country_code: event.country_code,
      browser_name: event.browser_name,
      browser_version: event.browser_version,
      platform_name: event.platform_name,
      device_name: event.device_name,
      user_agent: event.user_agent
    }
  end

  def pagination_meta
    { current_page: paginated.current_page, total_pages: paginated.total_pages, total_count: paginated.total_count }
  end
end
