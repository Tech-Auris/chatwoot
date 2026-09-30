# V1 simplification: binary signal — at least one user with `manager` role
# on the account was active in the dashboard within the last 7 days. When
# the account has no manager role at all, marks as `missing` so the weight
# gets redistributed (only ~half of small clinics have a dedicated manager).
#
# "Active" is read from `UserSession#last_activity_at`, which is bumped on
# every API request (throttled to 5min). Devise's `current_sign_in_at`
# only fires on password login and misses token-based session refreshes —
# managers who stay logged in but use the app daily would read as
# inactive months later.
class SuperAdmin::HealthScore::Metrics::ManagerEngagement < SuperAdmin::HealthScore::Metrics::Base
  RECENT_WINDOW_DAYS = 7

  def compute
    managers = manager_users
    return missing(:no_manager_role) if managers.empty?

    threshold = (on - RECENT_WINDOW_DAYS).beginning_of_day
    sessions = UserSession.where(user_id: managers.pluck(:id))
    last_activity = sessions.maximum(:last_activity_at)
    sub_score = last_activity && last_activity >= threshold ? 100 : 0

    present(
      sub_score,
      manager_count: managers.size,
      active_managers_7d: sessions.where(last_activity_at: threshold..).distinct.count(:user_id),
      last_activity_at: last_activity&.iso8601
    )
  end

  private

  def manager_users
    User.joins(:account_users).where(account_users: { account_id: account.id, role: AccountUser.roles[:manager] })
  end
end
