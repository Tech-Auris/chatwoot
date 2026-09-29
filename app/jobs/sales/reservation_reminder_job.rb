# On a reservation's last day, reminds the lead who hasn't closed yet, from
# the reminder time set in Commercial → Settings (12:30 by default, São Paulo
# time). Runs every 10 minutes; each reservation is reminded once per
# deadline — a renewed reservation gets reminded again on its new last day.
class Sales::ReservationReminderJob < ApplicationJob
  queue_as :low

  TIME_ZONE = 'America/Sao_Paulo'.freeze
  DEFAULT_TIME = '12:30'.freeze
  # Still open deals: reserved, details filled in, or terms signed but unpaid.
  OPEN_STATUSES = %i[reserved details_confirmed signed].freeze

  def perform
    now = Time.current.in_time_zone(TIME_ZONE)
    return if now < reminder_time_on(now)

    due_today(now.to_date).find_each do |quote|
      next if reminded?(quote, now.to_date)

      Sales::LeadWhatsappJob.perform_now(quote.id, 'last_day_reminder')
    end
  end

  private

  def reminder_time_on(now)
    hour, minute = (GlobalConfigService.load('COMMERCIAL_RESERVATION_REMINDER_TIME', nil).presence || DEFAULT_TIME).split(':').map(&:to_i)
    now.change(hour: hour, min: minute)
  end

  def due_today(date)
    zone = ActiveSupport::TimeZone[TIME_ZONE]
    SalesQuote.where(status: OPEN_STATUSES, reserved_until: zone.local(date.year, date.month, date.day).all_day)
  end

  def reminded?(quote, date)
    quote.events.where(event: %w[whatsapp_last_day_reminder_sent whatsapp_last_day_reminder_failed])
         .exists?(["metadata->>'reserved_on' = ?", date.iso8601])
  end
end
