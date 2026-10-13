require 'rails_helper'

RSpec.describe 'Marketing Integrations API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{id}/marketing_integrations' do
    let!(:integration) { create(:marketing_integration, account: account, status: :test_mode) }

    it 'returns unauthorized without a session' do
      get "/api/v1/accounts/#{account.id}/marketing_integrations"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses agents' do
      get "/api/v1/accounts/#{account.id}/marketing_integrations", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists integrations for administrators' do
      get "/api/v1/accounts/#{account.id}/marketing_integrations", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.first).to include('id' => integration.id, 'provider' => 'meta_capi', 'status' => 'test_mode')
    end

    # Sensitive credentials must never round-trip in plain text — the UI already
    # saw them when the operator pasted them in, and echoing back would let
    # anyone with an admin session read stored access tokens.
    it 'masks secret credentials in the response body' do
      integration.update!(credentials: integration.credentials.merge('ads_read_token' => 'EAAG_ads'))
      get "/api/v1/accounts/#{account.id}/marketing_integrations", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].first
      expect(payload['credentials']['ads_read_token']).to be_nil
      expect(payload['credentials_set']['ads_read_token']).to be(true)
    end
  end

  describe 'POST /api/v1/accounts/{id}/marketing_integrations' do
    # Pixels have their own endpoint; the Meta integration only keeps the
    # ads read token, so pixel keys sent here are dropped.
    it 'creates a Meta CAPI integration with just the ads read token' do
      post "/api/v1/accounts/#{account.id}/marketing_integrations",
           headers: admin.create_new_auth_token,
           params: {
             provider: 'meta_capi', status: 'active',
             credentials: { ads_read_token: 'EAAG_read', pixel_id: '999', access_token: 'EAAG' }
           },
           as: :json

      expect(response).to have_http_status(:success)
      integration = account.marketing_integrations.last
      expect(integration.provider).to eq('meta_capi')
      expect(integration.credentials).to eq('ads_read_token' => 'EAAG_read')
    end

    it 'creates a Google Ads Enhanced integration in active' do
      post "/api/v1/accounts/#{account.id}/marketing_integrations",
           headers: admin.create_new_auth_token,
           params: {
             provider: 'google_ads_enhanced', status: 'active',
             credentials: {
               customer_id: '111', conversion_action_id: '222',
               developer_token: 'DEV', oauth_refresh_token: '1//REFR',
               login_customer_id: '333'
             }
           },
           as: :json

      expect(response).to have_http_status(:success)
      integration = account.marketing_integrations.last
      expect(integration.google_ads_enhanced?).to be(true)
      expect(integration.credentials['login_customer_id']).to eq('333')
    end

    it 'validates the credentials against the provider vocabulary' do
      post "/api/v1/accounts/#{account.id}/marketing_integrations",
           headers: admin.create_new_auth_token,
           params: { provider: 'google_ads_enhanced', status: 'active', credentials: { customer_id: '' } },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{id}/marketing_integrations/{id}' do
    let!(:integration) do
      create(:marketing_integration, account: account, status: :test_mode, credentials: { 'ads_read_token' => 'EAAG_read' })
    end

    it 'updates the status without touching credentials when they are omitted' do
      patch "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}",
            headers: admin.create_new_auth_token,
            params: { status: 'active' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(integration.reload.status).to eq('active')
      expect(integration.credentials['ads_read_token']).to eq('EAAG_read')
    end

    it 'merges credentials rather than overwriting the whole hash' do
      patch "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}",
            headers: admin.create_new_auth_token,
            params: { credentials: { ad_account_id: '555' } },
            as: :json

      expect(integration.reload.credentials).to include('ads_read_token' => 'EAAG_read', 'ad_account_id' => '555')
    end
  end

  describe 'DELETE /api/v1/accounts/{id}/marketing_integrations/{id}' do
    let!(:integration) { create(:marketing_integration, account: account) }

    it 'destroys the integration' do
      expect do
        delete "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(MarketingIntegration, :count).by(-1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /api/v1/accounts/{id}/marketing_integrations/{id}/pixel_events' do
    let!(:integration) { create(:marketing_integration, account: account, status: :test_mode) }

    before do
      create(:marketing_pixel, marketing_integration: integration, pixel_id: '123456789')
      stub_request(:get, %r{graph\.facebook\.com/v20\.0/123456789/stats})
        .to_return(status: 200, body: { data: [{ 'data' => { 'AgendarConsulta' => 4 } }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the standard catalog plus the pixel-received custom events' do
      get "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}/pixel_events",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['standard']).to include('Lead', 'Purchase')
      expect(body['custom']).to contain_exactly('AgendarConsulta')
    end

    it 'refuses agents' do
      get "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}/pixel_events",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a Google Ads integration — the endpoint is Meta-only' do
      google = create(:marketing_integration, :google_ads, account: account)

      get "/api/v1/accounts/#{account.id}/marketing_integrations/#{google.id}/pixel_events",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
