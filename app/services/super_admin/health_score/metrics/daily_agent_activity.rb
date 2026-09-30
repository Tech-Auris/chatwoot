# % of business days (Mon-Fri) in the last 14d with at least one outgoing
# message sent by a User (agent/manager/admin) on the account. "Active" =
# the team actually engaged with conversations that day, not just opened
# the dashboard. The raw payload also carries the agents' dashboard activity
# (`UserSession#last_activity_at`, not the last password login) so the
# operator can tell "nobody opens the panel" from "they open it but don't reply".
class SuperAdmin::HealthScore::Metrics::DailyAgentActivity < SuperAdmin::HealthScore::Metrics::Base
  WINDOW_DAYS = 14
  RECENT_WINDOW_DAYS = 7

  def compute
    days = business_days
    return present(0, active_days: 0, business_days: days.size, active_dates: [], **agent_activity) if days.empty?

    active_dates = days.select { |day| any_outgoing_user_message?(day) }
    pct = active_dates.size.to_f / days.size
    sub_score = (pct * 100).round

    present(sub_score, active_days: active_dates.size, business_days: days.size, active_dates: active_dates.map(&:iso8601), **agent_activity)
  end

  private

  def agent_activity
    agent_ids = account.account_users.agent.pluck(:user_id)
    sessions = UserSession.where(user_id: agent_ids)
    threshold = (on - RECENT_WINDOW_DAYS).beginning_of_day

    {
      agent_count: agent_ids.size,
      active_agents_7d: sessions.where(last_activity_at: threshold..).distinct.count(:user_id),
      last_agent_activity_at: sessions.maximum(:last_activity_at)&.iso8601
    }
  end

  def business_days
    ((on - WINDOW_DAYS + 1)..on).reject { |d| d.saturday? || d.sunday? }
  end

  def any_outgoing_user_message?(day)
    Message.exists?(account_id: account.id,
                    message_type: :outgoing,
                    sender_type: 'User',
                    created_at: day.all_day)
  end
end
