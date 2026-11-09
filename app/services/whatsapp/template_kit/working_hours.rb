# The inbox's business hours as the kit writes them in a pt_BR template.
module Whatsapp::TemplateKit::WorkingHours
  DAY_NAMES = %w[domingo segunda terça quarta quinta sexta sábado].freeze

  module_function

  # "segunda a sexta, das 9h às 18h; sábado, das 8h às 12h". Nil while the
  # inbox has no business hours set up, so the placeholder stays visible.
  def text(inbox)
    return unless inbox.working_hours_enabled?

    open_days = inbox.weekly_schedule.reject { |day| day['closed_all_day'] }
    return if open_days.empty?

    open_days.chunk_while { |a, b| b['day_of_week'] == a['day_of_week'] + 1 && hours_label(a) == hours_label(b) }
             .map { |run| "#{days_label(run)}, #{hours_label(run.first)}" }
             .join('; ')
  end

  def days_label(run)
    first = DAY_NAMES[run.first['day_of_week']]
    return first if run.size == 1

    "#{first}#{run.size == 2 ? ' e ' : ' a '}#{DAY_NAMES[run.last['day_of_week']]}"
  end

  def hours_label(day)
    return '24 horas' if day['open_all_day']

    "das #{time_label(day['open_hour'], day['open_minutes'])} às #{time_label(day['close_hour'], day['close_minutes'])}"
  end

  def time_label(hour, minutes)
    minutes.to_i.zero? ? "#{hour}h" : format('%<hour>dh%<minutes>02d', hour: hour, minutes: minutes)
  end
end
