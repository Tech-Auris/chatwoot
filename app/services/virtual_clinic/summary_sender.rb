# Sends one of Helena's or Luciano's summaries to the person who asked for
# it: the numbers of the period that just ended (the clinic's, or the ads'),
# as an alert only they see (the teammate's "!" and chat) and a notification.
class VirtualClinic::SummarySender
  def initialize(summary, period, now)
    @summary = summary
    @account = summary.account
    @period = period
    @now = now
  end

  def perform
    return if sent?

    alert = @account.virtual_clinic_alerts.create!(persona: @summary.persona, rule: rule, user: @summary.user, payload: payload)
    NotificationBuilder.new(notification_type: 'virtual_clinic_alert', user: @summary.user, account: @account, primary_actor: alert).perform
    VirtualClinic::AlertBroadcast.new(@account, [@summary.user]).perform
  end

  private

  def sent?
    @account.virtual_clinic_alerts.exists?(user: @summary.user, rule: rule, created_at: @now.beginning_of_hour..)
  end

  def rule
    @summary.marketing? ? "marketing_#{@period}_summary" : "#{@period}_summary"
  end

  def range
    case @period
    when 'weekly' then @now.prev_week.all_week
    when 'monthly' then @now.prev_month.all_month
    else @now.yesterday.all_day
    end
  end

  def payload
    @summary.marketing? ? marketing_payload : clinic_payload
  end

  def marketing_payload
    numbers = VirtualClinic::MarketingNumbers.new(@account, range.begin, range.end).to_h
    numbers.merge(spend: reais(numbers[:spend]), cost_per_appointment: reais(numbers[:cost_per_appointment]))
  end

  def reais(value)
    value ? ActiveSupport::NumberHelper.number_to_currency(value, unit: 'R$ ', separator: ',', delimiter: '.') : '—'
  end

  def clinic_payload
    from = range.begin
    to = range.end
    home = V2::Reports::HomeBuilder.new(account: @account, account_user: AccountUser.new(account: @account, role: :administrator),
                                        params: { since: from.to_i, until: to.to_i })
    { leads: home.section('leads')[:leads][:total], appointments: home.section('appointments')[:appointments][:total],
      conversations: @account.conversations.where(created_at: from..to).count,
      follow_ups: @account.follow_ups.delivery_sent.where(created_at: from..to).count }
  end
end
