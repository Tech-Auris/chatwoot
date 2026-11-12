require 'rails_helper'

RSpec.describe 'MCP OAuth', type: :request do
  let(:account) { create(:account, mcp_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:redirect_uri) { 'https://claude.ai/api/mcp/auth_callback' }
  let(:verifier) { SecureRandom.urlsafe_base64(32) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
  let(:client) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: redirect_uri, scopes: 'mcp:read', confidential: false)
  end
  let(:authorization_params) do
    { response_type: 'code', client_id: client.uid, redirect_uri: redirect_uri, scope: 'mcp:read',
      state: 'xyz', code_challenge: challenge, code_challenge_method: 'S256' }
  end

  def authorize_as(user, approve: true)
    post '/api/v1/oauth/authorization', params: authorization_params.merge(approve: approve), headers: user.create_new_auth_token, as: :json
    URI(response.parsed_body['redirect_url'])
  end

  def exchange(code)
    post '/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri,
                                   client_id: client.uid, code_verifier: verifier }
    response.parsed_body
  end

  def token_for(user)
    code = Rack::Utils.parse_query(authorize_as(user).query)['code']
    exchange(code)['access_token']
  end

  it 'publishes the authorization server metadata' do
    get '/.well-known/oauth-authorization-server'

    expect(response.parsed_body).to include('registration_endpoint' => 'http://www.example.com/oauth/register',
                                            'code_challenge_methods_supported' => ['S256'],
                                            'scopes_supported' => ['mcp:read'])
  end

  describe 'client registration' do
    it 'registers a public client restricted to the read scope' do
      post '/oauth/register', params: { client_name: 'Claude', redirect_uris: [redirect_uri] }, as: :json

      expect(response).to have_http_status(:created)
      application = Doorkeeper::Application.find_by(uid: response.parsed_body['client_id'])
      expect(application).to have_attributes(confidential: false, name: 'Claude')
      expect(application.scopes.to_s).to eq('mcp:read')
      expect(response.parsed_body['token_endpoint_auth_method']).to eq('none')
    end

    it 'accepts localhost over http and refuses other plain http callbacks' do
      post '/oauth/register', params: { redirect_uris: ['http://localhost:4567/callback'] }, as: :json
      expect(response).to have_http_status(:created)

      post '/oauth/register', params: { redirect_uris: ['http://evil.example.com/callback'] }, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'GET /oauth/authorize' do
    it 'hands a valid request over to the dashboard consent page' do
      get '/oauth/authorize', params: authorization_params

      expect(response).to redirect_to("/app/oauth/consent?#{authorization_params.to_query}")
    end

    # Paths containing "/auth" get the login pack, which has no consent page.
    it 'serves the consent page with the dashboard pack' do
      get '/app/oauth/consent', params: authorization_params

      expect(controller.instance_variable_get(:@application_pack)).to eq('dashboard')
    end

    it 'sends PKCE-less requests back to the client with an error' do
      get '/oauth/authorize', params: authorization_params.except(:code_challenge, :code_challenge_method)

      expect(response.location).to start_with(redirect_uri)
      expect(response.location).to include('error=invalid_request')
    end

    it 'never redirects to a callback the client did not register' do
      get '/oauth/authorize', params: authorization_params.merge(redirect_uri: 'https://evil.example.com/cb')

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'consent' do
    it 'describes the request for the consent screen' do
      get '/api/v1/oauth/authorization', params: authorization_params, headers: admin.create_new_auth_token

      expect(response.parsed_body).to eq('client_name' => 'Claude', 'accounts' => [{ 'id' => account.id, 'name' => account.name }])
    end

    it 'issues a code an administrator approves, which PKCE turns into a read token' do
      location = authorize_as(admin)
      query = Rack::Utils.parse_query(location.query)
      expect(location.to_s).to start_with(redirect_uri)
      expect(query['state']).to eq('xyz')

      body = exchange(query['code'])
      expect(body).to include('token_type' => 'Bearer', 'expires_in' => 3600, 'scope' => 'mcp:read')
      expect(body['refresh_token']).to be_present
    end

    it 'refuses the code exchange with a wrong verifier' do
      code = Rack::Utils.parse_query(authorize_as(admin).query)['code']
      post '/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri,
                                     client_id: client.uid, code_verifier: 'wrong' }

      expect(response).to have_http_status(:bad_request)
    end

    it 'sends a denial back to the client' do
      location = authorize_as(admin, approve: false)

      expect(Rack::Utils.parse_query(location.query)).to include('error' => 'access_denied', 'state' => 'xyz')
    end

    it 'refuses agents and accounts with the MCP off' do
      agent = create(:user, account: account, role: :agent)
      other_admin = create(:user, account: create(:account), role: :administrator)

      [agent, other_admin].each do |user|
        post '/api/v1/oauth/authorization', params: authorization_params.merge(approve: true), headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'API access with the OAuth token' do
    let(:token) { token_for(admin) }
    let(:headers) { { api_access_token: token } }

    it 'reads the profile and the account' do
      get '/api/v1/profile', headers: headers, as: :json
      expect(response).to have_http_status(:success)

      get "/api/v1/accounts/#{account.id}/conversations/meta", headers: headers, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'cannot write' do
      post "/api/v1/accounts/#{account.id}/labels", params: { title: 'x' }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'stops reading the account once the MCP is turned off there' do
      token
      account.disable_mcp!

      get "/api/v1/accounts/#{account.id}/conversations/meta", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refreshes, and the user can revoke the connector from the profile' do
      token
      refresh = Rack::Utils.parse_query(authorize_as(admin).query)['code'].then { |code| exchange(code)['refresh_token'] }
      post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: refresh, client_id: client.uid }
      expect(response.parsed_body['access_token']).to be_present

      get '/api/v1/profile/oauth_applications', headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('name')).to eq(['Claude'])

      delete "/api/v1/profile/oauth_applications/#{client.id}", headers: admin.create_new_auth_token, as: :json
      get '/api/v1/profile', headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
