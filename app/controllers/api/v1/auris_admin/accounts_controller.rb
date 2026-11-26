# `index` finds an account by name or id. `secretary_context` returns
# everything that shapes how the AI behaves on one account, by section, so an
# operator can tune a prompt or diagnose a ticket from the MCP. Secrets only
# say whether they are filled in, never their value.
class Api::V1::AurisAdmin::AccountsController < Api::V1::AurisAdmin::BaseController
  SECTIONS = %w[account secretary follow_up ai_config prompts special_scenarios resources confirmations].freeze
  SEARCH_LIMIT = 20

  def index
    query = params[:q].to_s.strip
    accounts = Account.includes(account_secretary: :secretary_version).order(:name).limit(SEARCH_LIMIT)
    @accounts = query.match?(/\A\d+\z/) ? accounts.where(id: query) : accounts.where('accounts.name ILIKE ?', "%#{Account.sanitize_sql_like(query)}%")
  end

  def secretary_context
    @account = Account.find(params[:id])
    @sections = params[:sections].present? ? params[:sections].split(',') & SECTIONS : SECTIONS
    @inbox_names = @account.inboxes.pluck(:id, :name).to_h
    Rails.logger.info("[SuperAdminMcp] user=#{Current.user.id} read the setup of account=#{@account.id} sections=#{@sections.join(',')}")
  end
end
