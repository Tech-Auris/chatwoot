# Consent step of the MCP OAuth flow, called by the dashboard page
# /app/oauth/authorize with the logged-in user's session. `show` describes the
# request for the consent screen; `create` approves or denies it and answers
# the URL to send the browser back to the client.
class Api::V1::Oauth::AuthorizationsController < Api::BaseController
  before_action :set_pre_auth

  def show
    render json: {
      client_name: @pre_auth.client.name,
      accounts: Oauth::McpAccess.accounts_for(current_user).map { |account| { id: account.id, name: account.name } }
    }
  end

  def create
    if ActiveModel::Type::Boolean.new.cast(params[:approve])
      return render json: { error: I18n.t('errors.mcp.oauth_not_allowed') }, status: :forbidden if Oauth::McpAccess.accounts_for(current_user).empty?

      response = Doorkeeper::OAuth::CodeRequest.new(@pre_auth, current_user).authorize
    else
      response = Doorkeeper::OAuth::CodeRequest.new(@pre_auth, current_user).deny
    end

    render json: { redirect_url: response.redirect_uri }
  end

  private

  def set_pre_auth
    @pre_auth = Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.config, params.permit(*Oauth::AuthorizationsController::PARAMS).to_h,
                                                        current_user)
    render json: { error: @pre_auth.error_response.body[:error_description] }, status: :bad_request unless @pre_auth.authorizable?
  end
end
