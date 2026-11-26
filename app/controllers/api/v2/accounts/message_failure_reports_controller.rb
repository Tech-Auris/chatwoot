# Messages the account sent that failed in the period, grouped by inbox and by
# the provider's error, with the latest conversations of each group. Lets the
# MCP find every case of the same failure (e.g. Meta's 131042, payment issue)
# without opening each conversation on the screen.
class Api::V2::Accounts::MessageFailureReportsController < Api::V1::Accounts::BaseController
  PERIODS = { '7d' => 7, '30d' => 30, '90d' => 90 }.freeze
  CONVERSATIONS_PER_REASON = 5

  before_action :check_authorization

  def index
    groups = grouped_failures
    inbox_names = Current.account.inboxes.where(id: groups.keys.map(&:first)).pluck(:id, :name).to_h

    render json: {
      period: period_key,
      total: groups.values.sum { |rows| rows.sum(&:third) },
      inboxes: inboxes_payload(groups, inbox_names)
    }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def period_key
    PERIODS.key?(params[:period]) ? params[:period] : '7d'
  end

  def failed_messages
    scope = Current.account.messages.where(message_type: %i[outgoing template], status: :failed,
                                           created_at: PERIODS[period_key].days.ago..)
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    if params[:error].present?
      scope = scope.where("#{Messages::FailureReasons::ERROR_SQL} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:error])}%")
    end
    scope
  end

  # One row per inbox, error and conversation: [inbox_id, error, count, last_at, display_id],
  # grouped by [inbox_id, error].
  def grouped_failures
    failed_messages.reorder(nil).joins(:conversation)
                   .group(:inbox_id, Messages::FailureReasons::ERROR_SQL, 'conversations.display_id')
                   .pluck(:inbox_id, Messages::FailureReasons::ERROR_SQL, Arel.sql('COUNT(*)'),
                          Arel.sql('MAX(messages.created_at)'), 'conversations.display_id')
                   .group_by { |row| row.first(2) }
  end

  def inboxes_payload(groups, inbox_names)
    inboxes = groups.group_by { |(inbox_id, _error), _rows| inbox_id }.map do |inbox_id, reasons|
      reasons = reasons.map { |(_inbox_id, error), rows| reason_payload(error, rows) }.sort_by { |reason| -reason[:count] }
      { inbox_id: inbox_id, inbox_name: inbox_names[inbox_id], total: reasons.sum { |reason| reason[:count] }, reasons: reasons }
    end
    inboxes.sort_by { |inbox| -inbox[:total] }
  end

  def reason_payload(error, rows)
    latest = rows.sort_by { |row| -row.fourth.to_i }
    {
      error: error,
      count: rows.sum(&:third),
      last_at: latest.first.fourth.to_i,
      conversation_ids: latest.first(CONVERSATIONS_PER_REASON).map(&:fifth)
    }
  end
end
