# Read-only account setup for super admins (the Auris team), served under
# /api/v1/super_admin and read by the MCP Auris admin tools. Works with the
# personal access token and with the MCP OAuth token (GET only), across every
# account, whether or not the super admin is a member of it.
class Api::V1::AurisAdmin::BaseController < Api::BaseController
  before_action :ensure_super_admin

  private

  def ensure_super_admin
    render json: { error: 'Only super admins can read this' }, status: :forbidden unless Current.user.is_a?(::SuperAdmin)
  end
end
