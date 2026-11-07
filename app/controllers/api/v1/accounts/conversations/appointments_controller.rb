# The lead's appointments, for n8n to read and to fix them without moving the
# funnel stage (the patient reschedules but stays in "Agendado", or the amount
# paid comes in later). The body is the same `appointment` / `attendance` block
# the funnel move takes.
class Api::V1::Accounts::Conversations::AppointmentsController < Api::V1::Accounts::Conversations::BaseController
  REFERENCE_KEYS = [:id, :name].freeze
  APPOINTMENT_KEYS = [:source_id, :external_id, :scheduled_for, :status,
                      { professional: REFERENCE_KEYS, procedure: REFERENCE_KEYS }].freeze
  ATTENDANCE_KEYS = [:source_id, :external_id, :attended_at, { procedures: [:id, :name, :amount_paid] }].freeze

  def show
    @appointments = appointments
  end

  def update
    payload = params.permit(appointment: APPOINTMENT_KEYS, attendance: ATTENDANCE_KEYS)
    raise ArgumentError, I18n.t('funnel.appointments.block_required') if payload[:appointment].blank? && payload[:attendance].blank?

    Funnel::AppointmentUpsertService.new(
      conversation: @conversation,
      payload: payload[:attendance].presence || payload[:appointment],
      attendance: payload[:attendance].present?
    ).perform
    @appointments = appointments
    render :show
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def appointments
    @conversation.appointments.includes(:erp_source, :procedures).order(:scheduled_for, :id)
  end
end
