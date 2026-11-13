module AccessTokenAuthHelper
  BOT_ACCESSIBLE_ENDPOINTS = {
    'api/v1/accounts/conversations' => %w[toggle_status toggle_typing_status toggle_priority create update custom_attributes],
    'api/v1/accounts/conversations/messages' => ['create'],
    'api/v1/accounts/conversations/assignments' => ['create']
  }.freeze

  def ensure_access_token
    token = request.headers[:api_access_token] || request.headers[:HTTP_API_ACCESS_TOKEN]
    return if token.blank?

    @access_token = AccessToken.find_by(token: token)
    # Tokens the MCP connectors (claude.ai, ChatGPT) got through OAuth.
    @oauth_token = Doorkeeper::AccessToken.by_token(token) if @access_token.blank?
  end

  def authenticate_access_token!
    ensure_access_token
    return authenticate_oauth_token! if @oauth_token

    render_unauthorized('Invalid Access Token') && return if @access_token.blank?

    # NOTE: This ensures that current_user is set and available for the rest of the controller actions
    @resource = @access_token.owner
    Current.user = @resource if allowed_current_user_type?(@resource)
  end

  # OAuth tokens only read: GET requests, with the MCP scope, still valid.
  # The account they reach is checked in EnsureCurrentAccountHelper.
  def authenticate_oauth_token!
    return render_unauthorized('Invalid Access Token') unless @oauth_token.accessible? && @oauth_token.includes_scope?(Oauth::McpAccess::SCOPE)
    return render(json: { error: 'This token can only read data' }, status: :forbidden) unless request.get?

    @resource = User.find(@oauth_token.resource_owner_id)
    Current.user = @resource
  end

  def allowed_current_user_type?(resource)
    return true if resource.is_a?(User)
    return true if resource.is_a?(AgentBot)

    false
  end

  def validate_bot_access_token!
    return if Current.user.is_a?(User)
    return if @resource.is_a?(AgentBot) && agent_bot_accessible?

    render_unauthorized('Access to this endpoint is not authorized for bots')
  end

  def agent_bot_accessible?
    BOT_ACCESSIBLE_ENDPOINTS.fetch(params[:controller], []).include?(params[:action])
  end
end
