# Relatórios → Agendamentos: every open appointment (scheduled, rescheduled or
# confirmed) whose consultation falls in the period, nearest first, one row
# per appointment. Filters by professional and by ERP; the options come back
# with the rows so the screen fills its dropdowns. `summary` counts every
# appointment whose consultation falls in the period, whatever its status.
class Api::V2::Accounts::AppointmentReportsController < Api::V1::Accounts::BaseController
  PER_PAGE = 50
  TOP_LIMIT = 5
  WEEKDAY_SQL = "EXTRACT(DOW FROM appointments.scheduled_for AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::integer".freeze

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

  def summary
    scope = Current.account.appointments.where(scheduled_for: summary_range)
    totals = Appointment.statuses.keys.index_with(0).merge(scope.group(:status).count)
    render json: {
      totals: totals,
      no_show_rate: no_show_rate(totals),
      by_weekday: by_weekday(scope),
      top_professionals: top(scope, :professional_name),
      top_procedures: top(scope, :procedure_name)
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

  # Defaults to the last 30 days.
  def summary_range
    (parse_unix_timestamp(params[:since]) || 30.days.ago.beginning_of_day)..(parse_unix_timestamp(params[:until]) || Time.current)
  end

  def no_show_rate(totals)
    finished = totals['attended'] + totals['no_show']
    return nil if finished.zero?

    ((totals['no_show'].to_f / finished) * 100).round(2)
  end

  # Attendances and no-shows by weekday in Brasília time (0 = Sunday).
  def by_weekday(scope)
    counts = scope.where(status: %i[attended no_show]).group(Arel.sql(WEEKDAY_SQL), :status).count
    (0..6).map { |day| { weekday: day, attended: counts[[day, 'attended']] || 0, no_show: counts[[day, 'no_show']] || 0 } }
  end

  def top(scope, column)
    scope.where.not(column => [nil, '']).group(column).order(Arel.sql('COUNT(*) DESC'), column).limit(TOP_LIMIT).count
         .map { |name, count| { name: name, count: count } }
  end
end
