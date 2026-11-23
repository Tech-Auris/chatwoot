# What the AI team is doing now, for the balloons on the map and the team
# list: whether the secretary is serving patients (the n8n secretary: account
# active and secretary set up in Super Admin) and, if so, her open
# conversations and follow-ups waiting for the patient; and the manager's
# numbers of the month (same as the Home page); and the marketing
# teammate's ads of the month (Marketing → Analytics). It does not depend on the
# clinic's OpenAI key, which is only for talking to them.
class VirtualClinic::StatusBuilder
  CACHE_TTL = 30.seconds

  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
  end

  def build
    Rails.cache.fetch("virtual_clinic:status:#{@account.id}", expires_in: CACHE_TTL) do
      { secretary: { on_duty: on_duty?, off_duty_reason: off_duty_reason, active_conversations: active_conversations,
                     in_follow_up: @account.follow_ups.in_progress.count },
        manager: { month: month }, marketing: marketing }
    end
  end

  private

  def on_duty?
    off_duty_reason.nil?
  end

  # Why the secretary is not answering patients: the account status label
  # from Super Admin ("Sem pagamento", "IA desligada"…) or `not_set_up`.
  def off_duty_reason
    return AccountStatus.find_by(status: @account.status)&.label || @account.status unless @account.active?
    return 'not_set_up' if @account.account_secretary&.secretary_version.nil? || !@account.inboxes.exists?(secretary_enabled: true)

    nil
  end

  def active_conversations
    @account.conversations.open.where(assignee_id: Conversation.ai_user_id).count
  end

  def month_start
    Time.current.in_time_zone(@account.reporting_timezone.presence || 'America/Sao_Paulo').beginning_of_month
  end

  def month
    home = V2::Reports::HomeBuilder.new(account: @account, account_user: @account_user,
                                        params: { since: month_start.to_i, until: Time.current.to_i })
    leads = home.section('leads')[:leads][:total]
    appointments = home.section('appointments')[:appointments][:total]
    { leads: leads, appointments: appointments, conversion_rate: leads.zero? ? nil : (appointments * 100.0 / leads).round(1) }
  end

  # Ads that brought conversations or spent this month, and what one
  # appointment cost (in reais; nil without spend or appointments).
  def marketing
    rows = V2::Reports::CampaignAnalyticsBuilder.new(account: @account, params: { since: month_start.to_i.to_s, until: Time.current.to_i.to_s }).build
    spend = rows.sum { |row| row[:spend_cents].to_i }
    appointments = rows.sum { |row| row[:scheduled_count].to_i }
    { active_campaigns: rows.count { |row| (row[:conversations_count].to_i + row[:spend_cents].to_i).positive? },
      cost_per_appointment: cost_per(spend, appointments) }
  end

  def cost_per(spend_cents, count)
    (spend_cents / 100.0 / count).round(2) if spend_cents.positive? && count.positive?
  end
end
