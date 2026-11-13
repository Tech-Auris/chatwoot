class Api::V1::Accounts::ActivityLogsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25
  HISTORY_LIMIT = 50
  COLUMN_FILTERS = { auditable_type: :auditable_type, log_action: :action, source: :source }.freeze

  before_action :check_authorization

  def index
    @activity_logs = filtered_logs.recent_first.page(params[:page] || 1).per(PER_PAGE)
    @auditable_types = account_logs.distinct.order(:auditable_type).pluck(:auditable_type)
  end

  def show
    @activity_log = account_logs.find(params[:id])
    @history = account_logs.where(auditable_type: @activity_log.auditable_type, auditable_id: @activity_log.auditable_id)
                           .recent_first.limit(HISTORY_LIMIT)
  end

  def export
    service = ActivityLogs::ExportService.new(scope: filtered_logs)
    send_data service.perform, filename: service.filename, type: 'text/csv', disposition: 'attachment'
  end

  private

  def account_logs
    ActivityLog.where(account_id: Current.account.id)
  end

  def filtered_logs
    logs = within_period(account_logs)
    logs = logs.where(actor_type: %w[User SuperAdmin], actor_id: params[:user_id]) if params[:user_id].present?
    COLUMN_FILTERS.each { |param, column| logs = logs.where(column => params[param]) if params[param].present? }
    search(logs)
  end

  def within_period(logs)
    logs = logs.where(created_at: Time.zone.parse(params[:since])..) if params[:since].present?
    logs = logs.where(created_at: ..Time.zone.parse(params[:until])) if params[:until].present?
    logs
  end

  # A number searches the record id ("contato 4512"); text searches its name.
  def search(logs)
    query = params[:q].to_s.strip
    return logs if query.blank?

    record_id = query[/\d+/]
    return logs.where(auditable_id: record_id) if record_id

    logs.where('auditable_label ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
  end
end
