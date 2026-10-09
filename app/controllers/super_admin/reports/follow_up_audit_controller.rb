# Operations → FUP audit: how the n8n follow-ups are being processed across
# every account — when each one started, how long it took to go out
# (processed_at - created_at), what failed and what never confirmed.
class SuperAdmin::Reports::FollowUpAuditController < SuperAdmin::ApplicationController
  PERIODS = { '24h' => 24.hours, '7d' => 7.days, '30d' => 30.days }.freeze
  STUCK_AFTER = 5.minutes
  ISSUES_LIMIT = 100
  DURATION_SQL = 'EXTRACT(EPOCH FROM follow_ups.processed_at - follow_ups.created_at)'.freeze

  def show; end

  def data
    scope = follow_ups_scope
    render json: { totals: totals(scope), accounts: per_account(scope), issues: issues(scope) }
  end

  private

  def follow_ups_scope
    scope = FollowUp.where(created_at: (PERIODS.fetch(params[:period], 24.hours).ago)..)
    scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
    scope = scope.where(delivery_status: params[:delivery]) if FollowUp.delivery_statuses.key?(params[:delivery])
    scope
  end

  def stuck(scope)
    scope.delivery_pending.where(created_at: ...STUCK_AFTER.ago)
  end

  def totals(scope)
    stats = scope.pick(
      Arel.sql('COUNT(*)'), Arel.sql('COUNT(DISTINCT account_id)'),
      Arel.sql("COUNT(*) FILTER (WHERE delivery_status = #{FollowUp.delivery_statuses[:failed]})"),
      Arel.sql("AVG(#{DURATION_SQL})"), Arel.sql("MAX(#{DURATION_SQL})"),
      Arel.sql('COUNT(DISTINCT conversation_id)'),
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE outcome = #{FollowUp.outcomes[:reengaged]})")
    )
    total, accounts, failed, avg, max, conversations, reengaged = stats
    { total: total, accounts: accounts, failed: failed, avg_seconds: avg&.to_f&.round(1), max_seconds: max&.to_f&.round(1),
      stuck: stuck(scope).count, conversations: conversations, reengaged_conversations: reengaged }
  end

  def per_account(scope)
    rows = scope.group(:account_id).pluck(
      :account_id, Arel.sql('COUNT(*)'),
      Arel.sql("COUNT(*) FILTER (WHERE delivery_status = #{FollowUp.delivery_statuses[:failed]})"),
      Arel.sql("AVG(#{DURATION_SQL})"), Arel.sql('MAX(follow_ups.created_at)'),
      Arel.sql('COUNT(DISTINCT conversation_id)'),
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE outcome = #{FollowUp.outcomes[:reengaged]})")
    )
    accounts = Account.where(id: rows.map(&:first)).index_by(&:id)
    rows.map { |row| account_row(row, accounts[row.first]) }.sort_by { |row| -row[:total] }
  end

  def account_row(row, account)
    account_id, total, failed, avg, last_at, conversations, reengaged = row
    { account_id: account_id, account_name: account&.name, steps: Array(account&.settings&.dig('follow_up', 'steps')),
      total: total, failed: failed, avg_seconds: avg&.to_f&.round(1), last_at: last_at&.iso8601,
      conversations: conversations, reengaged_conversations: reengaged }
  end

  # Failed sends and FUPs that started but never confirmed, newest first.
  def issues(scope)
    scope.delivery_failed.or(stuck(scope)).includes(:account, :conversation)
         .order(created_at: :desc).limit(ISSUES_LIMIT).map { |follow_up| issue_row(follow_up) }
  end

  def issue_row(follow_up)
    { id: follow_up.id, created_at: follow_up.created_at.iso8601, account_id: follow_up.account_id,
      account_name: follow_up.account.name, conversation_id: follow_up.conversation.display_id,
      step: follow_up.step, delay_minutes: follow_up.delay_minutes, run_id: follow_up.run_id,
      delivery_status: follow_up.delivery_status, error_message: follow_up.error_message,
      duration_seconds: follow_up.processed_at && (follow_up.processed_at - follow_up.created_at).round(1) }
  end
end
