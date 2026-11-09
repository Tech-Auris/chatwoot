# Whether a moment falls inside a caixa's business hours, for any past moment
# (WorkingHour#open_at? only answers for today). A caixa with its schedule
# switched on uses it, in the caixa's timezone (set on the same screen); one
# without uses the Auris default, so the off-hours cards mean something from
# day one: weekdays 8h–18h and Saturday 8h–12h in the account's timezone —
# many old caixas still carry Chatwoot's original UTC timezone.
class V2::Reports::Home::BusinessHours
  # day_of_week (0 = Sunday) => [opens, closes] in minutes of the day.
  DEFAULT_SCHEDULE = {
    1 => [8 * 60, 18 * 60], 2 => [8 * 60, 18 * 60], 3 => [8 * 60, 18 * 60],
    4 => [8 * 60, 18 * 60], 5 => [8 * 60, 18 * 60], 6 => [8 * 60, 12 * 60]
  }.freeze

  def initialize(inboxes:, fallback_zone:)
    @schedules = inboxes.index_by(&:id).transform_values { |inbox| schedule_for(inbox) }
    @zones = inboxes.index_by(&:id).transform_values { |inbox| zone_for(inbox, fallback_zone) }
  end

  def open_at?(inbox_id, time)
    local = time.in_time_zone(@zones.fetch(inbox_id))
    opens, closes = @schedules.fetch(inbox_id)[local.wday]
    return false if opens.nil?

    minute = (local.hour * 60) + local.min
    minute >= opens && minute < closes
  end

  private

  def zone_for(inbox, fallback_zone)
    return fallback_zone unless inbox.working_hours_enabled?

    ActiveSupport::TimeZone[inbox.timezone.to_s] || fallback_zone
  end

  def schedule_for(inbox)
    return DEFAULT_SCHEDULE unless inbox.working_hours_enabled?

    inbox.working_hours.each_with_object({}) do |hours, schedule|
      next if hours.closed_all_day?

      schedule[hours.day_of_week] = hours.open_all_day? ? [0, 24 * 60] : day_range(hours)
    end
  end

  def day_range(hours)
    [(hours.open_hour.to_i * 60) + hours.open_minutes.to_i, (hours.close_hour.to_i * 60) + hours.close_minutes.to_i]
  end
end
