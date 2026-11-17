# Relatórios → Agendamentos: every open appointment (scheduled, rescheduled or
# confirmed) whose consultation falls in the period, nearest first, one row
# per appointment. Filters by professional and by ERP; the options come back
# with the rows so the screen fills its dropdowns.
class Api::V2::Accounts::AppointmentReportsController < Api::V1::Accounts::BaseController
  PER_PAGE = 50

  before_action :check_authorization

  def index
    scope = appointments_scope
    render json: {
      rows: scope.includes(:erp_source, :contact, conversation: :inbox)
                 .order(:scheduled_for, :id).offset((current_page - 1) * PER_PAGE).limit(PER_PAGE).map { |a| row(a) },
      filters: filter_options,
      meta: { current_page: current_page, per_page: PER_PAGE, total_count: scope.count }
    }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def appointments_scope
    scope = open_appointments.where(scheduled_for: report_range)
    scope = scope.where(professional_name: params[:professional]) if params[:professional].present?
    scope = scope.where(erp_source_id: params[:erp_source_id]) if params[:erp_source_id].present?
    scope
  end

  def open_appointments
    Current.account.appointments.open
  end

  # Defaults to the next 30 days.
  def report_range
    (parse_unix_timestamp(params[:from]) || Time.current.beginning_of_day)..(parse_unix_timestamp(params[:to]) || 30.days.from_now)
  end

  def parse_unix_timestamp(raw)
    Time.zone.at(raw.to_i) if raw.present?
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def filter_options
    {
      professionals: open_appointments.where.not(professional_name: [nil, '']).distinct.order(:professional_name).pluck(:professional_name),
      erp_sources: ErpSource.where(id: open_appointments.select(:erp_source_id)).order(:name).map { |s| { id: s.id, name: s.name } }
    }
  end

  def row(appointment)
    conversation = appointment.conversation
    {
      id: appointment.id,
      scheduled_for: appointment.scheduled_for&.iso8601,
      status: appointment.status,
      professional_name: appointment.professional_name,
      procedure_name: appointment.procedure_name,
      source_name: appointment.erp_source&.name,
      contact_name: appointment.contact.name,
      contact_phone: appointment.contact.phone_number,
      conversation_id: conversation.display_id,
      inbox_name: conversation.inbox.name
    }
  end
end
