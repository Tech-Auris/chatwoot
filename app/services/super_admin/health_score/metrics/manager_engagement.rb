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
    last_activity = last_activity_for(managers.pluck(:id))
    sub_score = last_activity && last_activity >= threshold ? 100 : 0

    present(
      sub_score,
      manager_count: managers.size,
      recent_login: sub_score == 100,
      last_activity_at: last_activity&.iso8601
    )
  end

  private

  def manager_users
    User.joins(:account_users).where(account_users: { account_id: account.id, role: AccountUser.roles[:manager] })
  end

  def last_activity_for(user_ids)
    return nil if user_ids.empty?

    UserSession.where(user_id: user_ids).maximum(:last_activity_at)
  end
end
