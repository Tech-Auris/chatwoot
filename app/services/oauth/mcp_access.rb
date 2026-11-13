# Who may use the Auris MCP through OAuth: administrators and managers of an
# account that has the MCP turned on. Checked when the user authorizes a
# connector and again on every API request made with its token.
module Oauth::McpAccess
  ROLES = %w[administrator manager].freeze
  SCOPE = 'mcp:read'.freeze

  module_function

  def allowed?(account_user)
    account_user.present? && ROLES.include?(account_user.role) && account_user.account.mcp_enabled
  end

  def accounts_for(user)
    user.account_users.includes(:account).select { |account_user| allowed?(account_user) }.map(&:account)
  end
end
