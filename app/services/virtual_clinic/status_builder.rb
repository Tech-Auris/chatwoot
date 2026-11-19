# What the AI team is doing now, for the balloons on the map and the team
# list: the secretary's open conversations and follow-ups waiting for the
# patient, and the manager's numbers of the month (same as the Home page).
class VirtualClinic::StatusBuilder
  CACHE_TTL = 30.seconds

  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
  end

  def build
    Rails.cache.fetch("virtual_clinic:status:#{@account.id}", expires_in: CACHE_TTL) do
      { secretary: { active_conversations: active_conversations, in_follow_up: @account.follow_ups.in_progress.count },
        manager: { month: month } }
    end
  end

  private

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
end
