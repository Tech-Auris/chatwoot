# Helena: of the appointments of the last 7 days that already happened, more
# than 15% were no-shows.
class VirtualClinic::Alerts::NoShowRate < VirtualClinic::Alerts::DailyRule
  MIN_APPOINTMENTS = 5

  def payload
    limit = setting(:no_show_rate, 15).to_f
    done = account.appointments.where(scheduled_for: (@now - 7.days)..@now, status: %w[attended no_show])
    total = done.count
    no_shows = done.no_show.count
    return if total < MIN_APPOINTMENTS || no_shows * 100.0 / total <= limit

    { rate: (no_shows * 100.0 / total).round(1), no_shows: no_shows, total: total }
  end
end
