class Api::V2::Accounts::IaHumanDistributionReportsController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MAX_RANGE_DAYS = 7

  before_action :check_authorization

  def index
    from = parse_unix_timestamp(params[:from])
    to = parse_unix_timestamp(params[:to])
    range = clamp_range(from, to)
    inbox_id = params[:inbox_id].presence&.to_i

    rows = build_rows(range, inbox_id, params[:date_basis])
    render json: { rows: rows, totals: tally(rows) }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # Audit window matches the operational retention we expect for
  # `ai_assignment_attempts` (deletes outside this window happen via a
  # separate housekeeping job — not modelled here). Clamping keeps a
  # "Last 30 days" picker from returning surprises.
  def clamp_range(from, to)
    finish = [to, Time.current].compact.min
    start = [from, finish - MAX_RANGE_DAYS.days].compact.max
    start..finish
  end

  def parse_unix_timestamp(raw)
    return nil if raw.blank?

    Time.zone.at(raw.to_i)
  end

  # `date_basis` picks what the date range filters on: when the IA handed the
  # conversation over (default), or when the lead's conversation was created —
  # the latter lists every handover of the leads that came in that period.
  def build_rows(range, inbox_id, date_basis)
    scope = AiAssignmentAttempt
            .for_account(Current.account.id)
            .includes(:conversation, :team, :agent_assigned)
            .order(:created_at)
    scope = if date_basis == 'lead_created'
              scope.joins(:conversation).where(conversations: { created_at: range })
            else
              scope.where(created_at: range)
            end
    scope = scope.for_inbox(inbox_id) if inbox_id

    scope.map { |attempt| build_row(attempt) }
  end

  def build_row(attempt)
    in_brt = attempt.created_at.in_time_zone(TZ)
    status_tag = attempt.status_tag
    {
      timestamp: in_brt.iso8601,
      date_label: in_brt.strftime('%d/%m/%Y'),
      time_label: in_brt.strftime('%H:%M:%S'),
      lead_created_label: lead_created_label(attempt.conversation),
      conversation_id: attempt.conversation&.display_id,
      inbox_id: attempt.conversation&.inbox_id,
      inbox_name: attempt.conversation&.inbox&.name,
      team_id: attempt.team_id,
      team_name: attempt.team&.name,
      agent_id: attempt.agent_assigned_id,
      agent_name: attempt.agent_assigned&.name,
      online_team_members: online_member_names(attempt.online_user_ids),
      status_tag: status_tag,
      status_text: status_text_for(status_tag)
    }
  end

  def lead_created_label(conversation)
    return if conversation.blank?

    conversation.created_at.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M:%S')
  end

  def online_member_names(user_ids)
    return [] if user_ids.blank?

    User.where(id: user_ids).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  def status_text_for(tag)
    {
      'assigned_via_team' => 'atribuído via time',
      'assigned_via_team_offline' => 'atribuído via time (agente offline)',
      'failed_no_online' => 'não conseguiu atribuir - ninguém ativo',
      'failed_with_online' => 'não conseguiu atribuir'
    }[tag]
  end

  def tally(rows)
    by_tag = rows.group_by { |r| r[:status_tag] }.transform_values(&:size)
    {
      total: rows.size,
      assigned_via_team: by_tag['assigned_via_team'] || 0,
      assigned_via_team_offline: by_tag['assigned_via_team_offline'] || 0,
      failed_with_online: by_tag['failed_with_online'] || 0,
      failed_no_online: by_tag['failed_no_online'] || 0
    }
  end
end
