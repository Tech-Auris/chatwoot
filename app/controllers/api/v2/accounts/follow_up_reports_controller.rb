# Relatórios → Follow-up: the FUPs the n8n workflow sent in the period, how
# many conversations got one and how many patients came back. The period,
# hour, inbox and contact filters all apply to when the FUP was sent; "total
# conversations" counts the conversations started in the period, as the IA →
# Humano report does with its leads.
class Api::V2::Accounts::FollowUpReportsController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  PER_PAGE = 50
  CSV_LIMIT = 10_000

  before_action :check_authorization

  def index
    scope = follow_ups_scope
    respond_to do |format|
      format.json do
        render json: { rows: page_rows(scope), totals: totals(scope), steps: steps(scope),
                       meta: { current_page: current_page, per_page: PER_PAGE, total_count: scope.count } }
      end
      format.csv { send_data csv(scope), filename: 'follow-ups.csv', type: 'text/csv' }
    end
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def report_range
    (parse_unix_timestamp(params[:from]) || Time.current.beginning_of_day)..(parse_unix_timestamp(params[:to]) || Time.current)
  end

  def parse_unix_timestamp(raw)
    Time.zone.at(raw.to_i) if raw.present?
  end

  def inbox_id
    params[:inbox_id].presence&.to_i
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def follow_ups_scope
    scope = Current.account.follow_ups.where(created_at: report_range)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope = filter_hours(scope)
    scope = filter_contact(scope) if params[:q].present?
    scope
  end

  # Hours in Brasília time, both ends included (7 and 9 = 07:00 to 09:59).
  def filter_hours(scope)
    hour_from = params[:hour_from].presence&.to_i
    hour_to = params[:hour_to].presence&.to_i
    return scope if hour_from.nil? && hour_to.nil?

    hour_sql = "EXTRACT(HOUR FROM follow_ups.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')"
    scope = scope.where("#{hour_sql} >= ?", hour_from) if hour_from
    scope = scope.where("#{hour_sql} <= ?", hour_to) if hour_to
    scope
  end

  # Name, or phone typed with or without formatting.
  def filter_contact(scope)
    term = params[:q].strip
    digits = term.gsub(/\D/, '')
    contacts = Current.account.contacts.where('contacts.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    if digits.size >= 4
      contacts = contacts.or(Current.account.contacts.where("regexp_replace(contacts.phone_number, '\\D', '', 'g') LIKE ?",
                                                            "%#{digits}%"))
    end
    scope.joins(:conversation).where(conversations: { contact_id: contacts.select(:id) })
  end

  def totals(scope)
    conversations = Current.account.conversations.where(created_at: report_range)
    conversations = conversations.where(inbox_id: inbox_id) if inbox_id
    {
      total_conversations: conversations.count,
      conversations_with_follow_up: scope.distinct.count(:conversation_id),
      reengaged_conversations: scope.outcome_reengaged.distinct.count(:conversation_id)
    }
  end

  # Reengagement by FUP number, with the waiting time most recently used for it.
  def steps(scope)
    scope.unscope(:order).group(:step).order(:step).pluck(
      :step,
      Arel.sql('(ARRAY_AGG(delay_minutes ORDER BY follow_ups.created_at DESC))[1]'),
      Arel.sql("COUNT(*) FILTER (WHERE delivery_status = #{FollowUp.delivery_statuses[:sent]})"),
      Arel.sql("COUNT(*) FILTER (WHERE outcome = #{FollowUp.outcomes[:reengaged]})")
    ).map { |step, delay, sent, reengaged| { step: step, delay_minutes: delay, sent: sent, reengaged: reengaged } }
  end

  def ordered(scope)
    scope.includes(:inbox, conversation: :contact).order(created_at: :desc, id: :desc)
  end

  def page_rows(scope)
    ordered(scope).page(current_page).per(PER_PAGE).map { |follow_up| build_row(follow_up) }
  end

  def build_row(follow_up)
    contact = follow_up.conversation.contact
    {
      id: follow_up.id,
      sent_at: follow_up.created_at.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M'),
      step: follow_up.step,
      delay_minutes: follow_up.delay_minutes,
      contact_name: contact&.name,
      contact_phone: contact&.phone_number,
      conversation_id: follow_up.conversation.display_id,
      inbox_name: follow_up.inbox.name,
      delivery_status: follow_up.delivery_status,
      error_message: follow_up.error_message,
      outcome: follow_up.outcome
    }
  end

  def csv(scope)
    CSV.generate do |rows|
      rows << ['Data/hora', 'FUP', 'Espera (min)', 'Contato', 'Telefone', 'Conversa', 'Caixa de entrada', 'Envio', 'Erro', 'Resultado']
      ordered(scope).limit(CSV_LIMIT).each do |follow_up|
        row = build_row(follow_up)
        rows << [row[:sent_at], row[:step], row[:delay_minutes], row[:contact_name], row[:contact_phone], row[:conversation_id],
                 row[:inbox_name], row[:delivery_status], row[:error_message], row[:outcome]]
      end
    end
  end
end
