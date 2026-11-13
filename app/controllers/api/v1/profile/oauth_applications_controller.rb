# AI assistants (MCP connectors) the user authorized, with a way to cut each.
class Api::V1::Profile::OauthApplicationsController < Api::BaseController
  def index
    tokens = Doorkeeper::AccessToken.where(resource_owner_id: current_user.id, revoked_at: nil)
    applications = Doorkeeper::Application.where(id: tokens.select(:application_id))
    connected_at = tokens.group(:application_id).minimum(:created_at)

    render json: applications.map { |application|
      { id: application.id, name: application.name, connected_at: connected_at[application.id].to_i }
    }
  end

  def destroy
    application = Doorkeeper::Application.find(params[:id])
    Doorkeeper::AccessToken.revoke_all_for(application.id, current_user)
    Doorkeeper::AccessGrant.revoke_all_for(application.id, current_user)
    head :ok
  end
end
