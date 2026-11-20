# "Bom dia da Helena": yesterday in numbers, at 8h, for the clinics that
# turned it on in the Clínica virtual settings.
class VirtualClinic::Alerts::DailySummary < VirtualClinic::Alerts::DailyRule
  SETTING = 'virtual_clinic_daily_summary'.freeze

  def due?
    account.settings[SETTING] == true
  end

  def payload
    from = @now.yesterday.beginning_of_day
    to = from.end_of_day
    numbers(from, to).merge(conversations: account.conversations.where(created_at: from..to).count,
                            follow_ups: account.follow_ups.delivery_sent.where(created_at: from..to).count)
  end
end
