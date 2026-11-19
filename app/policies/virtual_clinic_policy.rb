# Clínica virtual: the page is released per account (`virtual_clinic_enabled`)
# and open to every role, since the internal chat lives in it. The AI team
# inside it is for administrators and managers only, and needs the AI
# assistant (MCP) on plus the clinic's own OpenAI key.
class VirtualClinicPolicy < ApplicationPolicy
  def show?
    account.virtual_clinic_enabled?
  end

  def ai_team_visible?
    show? && (account_user.administrator? || account_user.manager?)
  end

  def ai_team?
    ai_team_visible? && missing_requirement.nil?
  end

  def update_settings?
    show? && account_user.administrator?
  end

  def missing_requirement
    return 'mcp' unless account.mcp_enabled?
    return 'openai_key' if self.class.openai_api_key(account).blank?

    nil
  end

  def self.openai_api_key(account)
    account.hooks.find_by(app_id: 'openai', status: 'enabled')&.settings&.dig('api_key')
  end
end
