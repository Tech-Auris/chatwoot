# Everything the Início page shows, for one user: the day summary, the
# indicator cards (a section at a time) and the caixas the numbers come from.
# Administrators and managers see every caixa of the account, agents only
# theirs, the same rule as the conversation list.
class V2::Reports::HomeBuilder
  DEFAULT_PERIOD = 7.days

  def initialize(account:, account_user:, params:)
    @account = account
    @account_user = account_user
    @params = params
  end

  # The top of the page: it ignores the filters, so the page only asks for it
  # when it opens and on the minute refresh.
  def build
    {
      timezone: home_scope.zone.tzinfo.name,
      available_inboxes: inbox_rows(permitted_inboxes),
      today: V2::Reports::Home::TodayBuilder.new(scope: home_scope).build
    }
  end

  # One section of the indicator cards, for the picked period and filters.
  def section(name)
    V2::Reports::Home::MetricsBuilder.new(scope: metrics_scope, period: period).section(name)
  end

  # The conversations behind one card, for its detail dialog.
  def drilldown(metric:, page:)
    V2::Reports::Home::Drilldown.new(
      today: V2::Reports::Home::TodayBuilder.new(scope: home_scope),
      metrics: V2::Reports::Home::MetricsBuilder.new(scope: metrics_scope, period: period),
      period: period, metric: metric, page: page
    ).build
  end

  private

  attr_reader :account, :account_user, :params

  def home_scope
    @home_scope ||= V2::Reports::Home::Scope.new(account: account, inbox_ids: permitted_inboxes.map(&:id))
  end

  def metrics_scope
    V2::Reports::Home::Scope.new(account: account, inbox_ids: selected_inboxes.map(&:id), origem: params[:origem])
  end

  def permitted_inboxes
    @permitted_inboxes ||= begin
      inboxes = account_user.administrator? || account_user.manager? ? account.inboxes : account_user.user.inboxes.where(account_id: account.id)
      inboxes.order(:name).to_a
    end
  end

  # Picked caixas outside the user's reach are ignored; none picked means all.
  def selected_inboxes
    ids = Array(params[:inbox_ids]).map(&:to_i)
    picked = permitted_inboxes.select { |inbox| ids.include?(inbox.id) }
    picked.presence || permitted_inboxes
  end

  def inbox_rows(inboxes)
    inboxes.map { |inbox| { id: inbox.id, name: inbox.name } }
  end

  def period
    @period ||= build_period
  end

  def build_period
    until_time = params[:until].present? ? Time.zone.at(params[:until].to_i) : Time.current
    since = params[:since].present? ? Time.zone.at(params[:since].to_i) : until_time - DEFAULT_PERIOD
    V2::Reports::Home::Period.new(since: since.in_time_zone(home_scope.zone), until_time: until_time.in_time_zone(home_scope.zone))
  end
end
