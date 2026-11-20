# Helena's rules look at the week, so they are checked once a day (9h, the
# first run of the job in that hour), not every 15 minutes.
class VirtualClinic::Alerts::DailyRule < VirtualClinic::Alerts::Rule
  CHECK_HOUR = 9
  COOLDOWN = 20.hours

  def persona
    'manager'
  end

  def due?
    @now.hour == CHECK_HOUR && @now.min < 15
  end

  private

  def numbers(from, to)
    # The whole clinic, as an administrator sees it.
    home = V2::Reports::HomeBuilder.new(account: account, account_user: AccountUser.new(account: account, role: :administrator),
                                        params: { since: from.to_i, until: to.to_i })
    { leads: home.section('leads')[:leads][:total], appointments: home.section('appointments')[:appointments][:total] }
  end
end
