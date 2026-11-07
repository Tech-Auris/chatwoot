# A procedure the patient closed at the appointment, with the total paid for it.
class AppointmentProcedure < ApplicationRecord
  belongs_to :appointment
  belongs_to :account
end
