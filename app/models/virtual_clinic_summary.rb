# Which of Helena's summaries a person wants and at what hour (in the
# clinic's time zone): daily (yesterday), weekly (on Mondays, last week) and
# monthly (on the 1st, last month). Sent by VirtualClinic::SummaryJob.
class VirtualClinicSummary < ApplicationRecord
  PERIODS = %w[daily weekly monthly].freeze

  belongs_to :account
  belongs_to :user

  validates :hour, inclusion: { in: 0..23 }
  validates :user_id, uniqueness: { scope: :account_id }

  # The summaries due at `now` (a time in the clinic's zone).
  def due_periods(now)
    return [] unless now.hour == hour

    PERIODS.select { |period| public_send(period) && starts?(period, now) }
  end

  private

  def starts?(period, now)
    case period
    when 'weekly' then now.monday?
    when 'monthly' then now.day == 1
    else true
    end
  end
end
