require 'rails_helper'

RSpec.describe 'Home API', type: :request do
  let(:account) { create(:account, home_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v2/accounts/:account_id/home' do
    it 'answers any user of the account' do
      get "/api/v2/accounts/#{account.id}/home", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to include('today', 'metrics', 'inboxes', 'available_inboxes')
    end

    it 'is not found while the page is off for the account' do
      account.update!(home_enabled: false)

      get "/api/v2/accounts/#{account.id}/home", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'lists the conversations behind a card' do
      create(:conversation, account: account, inbox: create(:inbox, account: account), created_at: 1.hour.ago)
      admin = create(:user, account: account, role: :administrator)

      get "/api/v2/accounts/#{account.id}/home/drilldown", params: { metric: 'leads' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['total_count']).to eq(1)
    end

    it 'answers an unknown card with unprocessable entity' do
      get "/api/v2/accounts/#{account.id}/home/drilldown", params: { metric: 'revenue' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses users outside the account' do
      get "/api/v2/accounts/#{account.id}/home", headers: create(:user).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
