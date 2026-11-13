# RFC 8414 authorization server metadata, read by MCP clients (claude.ai,
# ChatGPT, Claude Code) to find where to register, authorize and get tokens.
class Oauth::MetadataController < ActionController::API
  def show
    base = request.base_url
    render json: {
      issuer: base,
      authorization_endpoint: "#{base}/oauth/authorize",
      token_endpoint: "#{base}/oauth/token",
      registration_endpoint: "#{base}/oauth/register",
      revocation_endpoint: "#{base}/oauth/revoke",
      response_types_supported: ['code'],
      grant_types_supported: %w[authorization_code refresh_token],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
      scopes_supported: [Oauth::McpAccess::SCOPE]
    }
  end
end
