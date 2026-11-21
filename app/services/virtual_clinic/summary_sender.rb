# Sends one of Helena's summaries to the person who asked for it: the
# numbers of the period that just ended, as an alert only they see (her "!"
# and her chat) and a notification.
class VirtualClinic::SummarySender
  def initialize(summary, period, now)
    @summary = summary
    @account = summary.account
    @period = period
    @now = now
  end

  def perform
    return if sent?

    alert = @account.virtual_clinic_alerts.create!(persona: 'manager', rule: "#{@period}_summary", user: @summary.user, payload: payload)
    NotificationBuilder.new(notification_type: 'virtual_clinic_alert', user: @summary.user, account: @account, primary_actor: alert).perform
    VirtualClinic::AlertBroadcast.new(@account, [@summary.user]).perform
  end

  private

  def sent?
    @account.virtual_clinic_alerts.exists?(user: @summary.user, rule: "#{@period}_summary", created_at: @now.beginning_of_hour..)
  end

  def range
    case @period
    when 'weekly' then @now.prev_week.all_week
    when 'monthly' then @now.prev_month.all_month
    else @now.yesterday.all_day
    end
  end

  def payload
    from = range.begin
    to = range.end
    home = V2::Reports::HomeBuilder.new(account: @account, account_user: AccountUser.new(account: @account, role: :administrator),
                                        params: { since: from.to_i, until: to.to_i })
    { leads: home.section('leads')[:leads][:total], appointments: home.section('appointments')[:appointments][:total],
      conversations: @account.conversations.where(created_at: from..to).count,
      follow_ups: @account.follow_ups.delivery_sent.where(created_at: from..to).count }
  end
end
