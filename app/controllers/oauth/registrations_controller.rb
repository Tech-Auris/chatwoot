# RFC 7591 dynamic client registration: MCP clients register themselves as
# public clients (no secret, PKCE required) restricted to the read scope.
class Oauth::RegistrationsController < ActionController::API
  def create
    application = Doorkeeper::Application.create!(
      name: params[:client_name].presence&.truncate(100) || 'Assistente de IA',
      redirect_uri: Array(params[:redirect_uris]).join("\n"),
      scopes: Oauth::McpAccess::SCOPE,
      confidential: false
    )

    render json: {
      client_id: application.uid,
      client_name: application.name,
      redirect_uris: application.redirect_uri.split,
      grant_types: %w[authorization_code refresh_token],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      scope: application.scopes.to_s,
      client_id_issued_at: application.created_at.to_i
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_client_metadata', error_description: e.record.errors.full_messages.to_sentence }, status: :bad_request
  end
end
