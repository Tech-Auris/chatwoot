# Clara: follow-ups that failed to go out today (e.g. WhatsApp 131026).
class VirtualClinic::Alerts::FailedFollowUps < VirtualClinic::Alerts::Rule
  def payload
    count = account.follow_ups.delivery_failed.where(created_at: @now.beginning_of_day..).count
    { count: count } if count.positive?
  end
end
