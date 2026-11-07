# A consultation a clinic booked for a lead, as n8n reports it when it moves
# the funnel (see Funnel::AppointmentUpsertService). A lead may hold any number
# of them; `erp_source` + `external_id` identify one in the clinic's ERP or
# calendar, so resending the same booking updates it instead of adding another.
class Appointment < ApplicationRecord
  OPEN_STATUSES = %w[scheduled rescheduled confirmed].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :erp_source, optional: true
  has_many :procedures, class_name: 'AppointmentProcedure', dependent: :destroy

  enum :status, { scheduled: 0, rescheduled: 1, confirmed: 2, attended: 3, no_show: 4, canceled: 5 }

  scope :open, -> { where(status: OPEN_STATUSES) }
end
