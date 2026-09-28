class Api::V2::Accounts::IaHumanDistributionReportsController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  PER_PAGE = 50
  # Same rule as AiAssignmentAttempt#status_tag, in SQL, so the cards count the
  # whole period and not just the page on screen.
  STATUS_COUNTS_SQL = <<~SQL.squish.freeze
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE agent_assigned_id IS NOT NULL AND agent_assigned_id = ANY(online_user_ids)) AS assigned_via_team,
    COUNT(*) FILTER (WHERE agent_assigned_id IS NOT NULL AND NOT (agent_assigned_id = ANY(online_user_ids))) AS assigned_via_team_offline,
    COUNT(*) FILTER (WHERE agent_assigned_id IS NULL AND cardinality(online_user_ids) > 0) AS failed_with_online,
    COUNT(*) FILTER (WHERE agent_assigned_id IS NULL AND cardinality(online_user_ids) = 0) AS failed_no_online
  SQL

  before_action :check_authorization

  def index
    range = report_range
    inbox_id = params[:inbox_id].presence&.to_i
    scope = attempts_scope(range, inbox_id, params[:date_basis])
    totals = status_counts(scope)
    totals[:leads_created] = leads_created_count(range, inbox_id) if params[:date_basis] == 'lead_created'

    render json: { rows: page_rows(scope), totals: totals,
                   meta: { current_page: current_page, per_page: PER_PAGE, total_count: totals[:total] } }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # Whatever period the filter asks for: the attempts are kept for good.
  def report_range
    (parse_unix_timestamp(params[:from]) || Time.current.beginning_of_day)..(parse_unix_timestamp(params[:to]) || Time.current)
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def page_rows(scope)
    scope.includes(:conversation, :team, :agent_assigned).page(current_page).per(PER_PAGE).map { |attempt| build_row(attempt) }
  end

  def parse_unix_timestamp(raw)
    return nil if raw.blank?

    Time.zone.at(raw.to_i)
  end

  # `date_basis` picks what the date range filters on: when the IA handed the
  # conversation over (default), or when the lead's conversation was created —
  # the latter lists every handover of the leads that came in that period.
  def attempts_scope(range, inbox_id, date_basis)
    scope = AiAssignmentAttempt.for_account(Current.account.id)
    # Newest first, on the same date the period is filtered by.
    scope = if date_basis == 'lead_created'
              scope.joins(:conversation).where(conversations: { created_at: range })
                   .order('conversations.created_at DESC', created_at: :desc, id: :desc)
            else
              scope.where(created_at: range).order(created_at: :desc, id: :desc)
            end
    inbox_id ? scope.for_inbox(inbox_id) : scope
  end

  def status_counts(scope)
    scope.unscope(:order).select(STATUS_COUNTS_SQL).take.attributes.except('id').symbolize_keys
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

  # Every lead (conversation) that came in during the range, handed over or not,
  # so the handovers can be read against how many leads there were.
  def leads_created_count(range, inbox_id)
    scope = Current.account.conversations.where(created_at: range)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope.count
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
end
