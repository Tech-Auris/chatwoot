# Clínica virtual: the page is released per account (`virtual_clinic_enabled`)
# and open to every role, since the internal chat lives in it. Everyone sees
# the AI team on the map; the numbers of the restricted teammates (the
# manager), their alerts, the editor and talking to the team are for
# administrators and managers. Talking also needs the AI assistant (MCP) on
# plus the clinic's own OpenAI key. Whether Clara is serving patients is a
# different thing (the n8n secretary, our key).
class VirtualClinicPolicy < ApplicationPolicy
  def show?
    account.virtual_clinic_enabled?
  end

  def ai_team_visible?
    show?
  end

  # Talking to the team, its alerts and the numbers of restricted teammates.
  def ai_team_manager?
    show? && (account_user.administrator? || account_user.manager?)
  end

  def ai_chat?
    ai_team_manager? && missing_requirement.nil?
  end

  def update_settings?
    show? && account_user.administrator?
  end

  # The clinic editor (furniture, rooms, the AI team's names and looks).
  def update_layout?
    ai_team_manager?
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
