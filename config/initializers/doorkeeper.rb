# OAuth 2.1 authorization server for the Auris MCP connectors.
#
# Doorkeeper only issues and refreshes tokens here (`/oauth/token`,
# `/oauth/revoke`). The authorization step lives on the dashboard: the
# dashboard login is token based, not a Rails session, so `/oauth/authorize`
# hands the request to the SPA consent page, which calls
# `Api::V1::Oauth::AuthorizationsController` (see `Oauth::McpAccess`).
Doorkeeper.configure do
  orm :active_record
  api_only
  base_controller 'ActionController::API'

  # Nobody authorizes through Doorkeeper's own controller (it is skipped).
  resource_owner_authenticator { nil }

  grant_flows %w[authorization_code]
  use_refresh_token
  access_token_expires_in 1.hour
  authorization_code_expires_in 5.minutes

  default_scopes 'mcp:read'
  enforce_configured_scopes

  # Public clients (claude.ai, ChatGPT, Claude Code) must use PKCE with S256.
  force_pkce
  pkce_code_challenge_methods %w[S256]

  hash_token_secrets
  hash_application_secrets

  # Claude Code and other local clients call back on localhost over http.
  force_ssl_in_redirect_uri { |uri| %w[localhost 127.0.0.1].exclude?(uri.host) }
end
