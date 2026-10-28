# "Horário da IA desligada": the hours in which a patient message hands the
# conversation to the inbox's team instead of the AI secretary.
module AiOffSchedulable
  extend ActiveSupport::Concern

  included do
    has_many :ai_off_hours, -> { order(:day_of_week, :from_minutes) }, class_name: 'InboxAiOffHour', dependent: :destroy, inverse_of: :inbox
    belongs_to :ai_schedule_team, class_name: 'Team', optional: true
  end

  def ai_off_now?(time = Time.current)
    return false unless ai_schedule_enabled?

    local = time.in_time_zone(effective_timezone)
    minute = (local.hour * 60) + local.min
    ai_off_hours.any? { |hour| hour.day_of_week == local.wday && minute >= hour.from_minutes && minute < hour.to_minutes }
  end
end
