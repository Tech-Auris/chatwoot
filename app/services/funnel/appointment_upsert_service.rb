# Records what n8n reports about a lead's consultation: the booking
# (`appointment` block) or the attendance with the procedures closed and the
# amount paid for each (`attendance` block). Called by
# Funnel::MoveConversationService inside the stage move, and by the
# conversation appointments endpoint to fix data without moving the stage.
#
# The appointment is found by `source_id` + `external_id`, so resending the
# same call updates it. Without `external_id` it falls back to the lead's only
# open appointment, and refuses when there is more than one. Keys left out
# keep their value; keys sent as null clear it.
class Funnel::AppointmentUpsertService
  # Stage name → status the appointment takes when the lead moves there.
  STAGE_STATUSES = {
    'Agendado' => 'scheduled',
    'Reagendado' => 'rescheduled',
    'Confirmado' => 'confirmed',
    'No-Show' => 'no_show',
    'Perdido' => 'canceled'
  }.freeze

  pattr_initialize [:conversation!, :payload!, { attendance: false, stage_name: nil }]

  def perform
    appointment.assign_attributes(conversation: conversation, contact_id: conversation.contact_id)
    attendance ? apply_attendance : apply_booking
    appointment.save!
    replace_procedures if attendance && attributes.key?(:procedures)
    appointment
  end

  private

  delegate :account, to: :conversation

  def attributes
    @attributes ||= payload.to_h.with_indifferent_access
  end

  def apply_booking
    previous_date = appointment.scheduled_for
    assign_time(:scheduled_for)
    assign_reference(:professional)
    assign_reference(:procedure)
    appointment.status = booking_status(previous_date)
  end

  def apply_attendance
    assign_time(:attended_at)
    appointment.attended_at ||= Time.current unless attributes.key?(:attended_at)
    appointment.status = 'attended'
  end

  # An explicit status wins, then the stage the lead moves to; a new date on an
  # existing booking is a reschedule.
  def booking_status(previous_date)
    return attributes[:status] if attributes[:status].present?
    return STAGE_STATUSES[stage_name] if STAGE_STATUSES.key?(stage_name)
    return 'scheduled' if appointment.new_record?
    return 'rescheduled' if previous_date.present? && appointment.scheduled_for != previous_date

    appointment.status
  end

  def assign_time(key)
    return unless attributes.key?(key)

    appointment[key] = attributes[key].presence && Time.zone.parse(attributes[key].to_s)
  end

  def assign_reference(kind)
    return unless attributes.key?(kind)

    reference = attributes[kind] || {}
    appointment["#{kind}_external_id"] = reference[:id]&.to_s
    appointment["#{kind}_name"] = reference[:name]
  end

  # Resending the attendance replaces the list, so amounts never add up twice.
  def replace_procedures
    appointment.procedures.delete_all
    Array(attributes[:procedures]).each do |procedure|
      appointment.procedures.create!(
        account: account,
        procedure_external_id: procedure[:id]&.to_s,
        procedure_name: procedure[:name],
        amount_paid_cents: to_cents(procedure[:amount_paid])
      )
    end
  end

  def to_cents(amount)
    return if amount.nil? || amount.to_s.strip.empty?

    (BigDecimal(amount.to_s) * 100).round.to_i
  end

  def appointment
    @appointment ||= external_id.present? ? find_by_external_id : only_open_appointment
  end

  def find_by_external_id
    account.appointments.find_or_initialize_by(erp_source_id: erp_source&.id, external_id: external_id)
  end

  def only_open_appointment
    open = conversation.appointments.open.to_a
    raise ArgumentError, I18n.t('funnel.appointments.external_id_required') if open.size > 1

    open.first || conversation.appointments.new(account: account, erp_source: erp_source)
  end

  def external_id
    attributes[:external_id].presence&.to_s
  end

  # `source_id` is the Supabase `integration_type` id, the same as
  # `erp_sources.id`; without it the booking comes from the account's ERP.
  def erp_source
    return @erp_source if defined?(@erp_source)

    @erp_source = if attributes[:source_id].present?
                    ErpSource.find_by(id: attributes[:source_id]) ||
                      raise(ArgumentError, I18n.t('funnel.appointments.invalid_source', source_id: attributes[:source_id]))
                  else
                    account.erp_source
                  end
  end
end
