# Who may use the Auris MCP through OAuth: administrators and managers of an
# account that has the MCP turned on. Super admins who are administrators of
# the account (the Auris team) may use it even with the MCP turned off, and
# super admins also get the admin tools over every account.
# Checked when the user authorizes a connector and again on every API request
# made with its token.
module Oauth::McpAccess
  ROLES = %w[administrator manager].freeze
  SCOPE = 'mcp:read'.freeze

  module_function

  def allowed?(account_user)
    return false unless account_user.present? && ROLES.include?(account_user.role)

    account_user.account.mcp_enabled || (account_user.administrator? && account_user.user.is_a?(SuperAdmin))
  end

  def accounts_for(user)
    user.account_users.includes(:account, :user).select { |account_user| allowed?(account_user) }.map(&:account)
  end

  # Super admins may connect even without any account: the MCP gives them the
  # read-only admin tools over every account (Api::V1::AurisAdmin).
  def can_authorize?(user)
    user.is_a?(SuperAdmin) || accounts_for(user).any?
  end
end
