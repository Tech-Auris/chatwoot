# Who used the dashboard in a period, for Super Admin → Login events →
# Atividade. A login event only exists when somebody types a password, and a
# session stays valid for months, so a user can work every day without one;
# `user_sessions.last_activity_at` is what says they were there.
#
# Only the last activity of each session is kept (no day-by-day history):
# exact for today, while a past day misses whoever used that session again
# afterwards.
#
# One row per user and account (the account filter and the role are an
# AccountUser matter), with the most recent session's IP and device.
class SuperAdmin::UserActivityService
  pattr_initialize [:from!, :to!, { account_id: nil, role: nil }]

  def rows
    latest = latest_session_by_user
    return [] if latest.empty?

    counts = sessions.group(:user_id).count
    account_users(latest.keys).map { |account_user| row(account_user, latest[account_user.user_id], counts[account_user.user_id]) }
                              .sort_by { |row| -row[:last_activity_at].to_f }
  end

  private

  def sessions
    UserSession.where(last_activity_at: from..to)
  end

  def latest_session_by_user
    sessions.order(:user_id, last_activity_at: :desc).select('DISTINCT ON (user_id) *').index_by(&:user_id)
  end

  def account_users(user_ids)
    scope = AccountUser.includes(:user, :account).where(user_id: user_ids)
    scope = scope.where(account_id: account_id) if account_id
    scope = scope.where(role: role) if role
    scope
  end

  def row(account_user, session, sessions_count)
    {
      id: account_user.id,
      last_activity_at: session.last_activity_at,
      session_started_at: session.created_at,
      sessions_count: sessions_count,
      user_id: account_user.user_id,
      user_name: account_user.user&.name,
      user_email: account_user.user&.email,
      account_id: account_user.account_id,
      account_name: account_user.account&.name,
      role: account_user.role,
      ip_address: session.ip_address,
      city: session.city,
      country: session.country,
      browser_name: session.browser_name,
      browser_version: session.browser_version,
      platform_name: session.platform_name,
      device_name: session.device_name
    }
  end
end
