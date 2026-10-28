# One range of a weekday in which the AI secretary is off in the inbox, in
# minutes from midnight in the inbox's timezone. A range past midnight is
# saved as two ranges, one on each day.
class InboxAiOffHour < ApplicationRecord
  belongs_to :inbox

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :from_minutes, :to_minutes, inclusion: { in: 0..1440 }
  validate :ends_after_start

  private

  def ends_after_start
    errors.add(:to_minutes, :greater_than, count: from_minutes) if from_minutes && to_minutes && to_minutes <= from_minutes
  end
end
