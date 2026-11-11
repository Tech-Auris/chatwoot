require 'rails_helper'

RSpec.describe 'Home API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v2/accounts/:account_id/home' do
    it 'answers any user of the account' do
      get "/api/v2/accounts/#{account.id}/home", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to contain_exactly('timezone', 'today', 'available_inboxes')
    end

    it 'answers one section of the cards' do
      create(:conversation, account: account, inbox: create(:inbox, account: account), created_at: 1.hour.ago)
      admin = create(:user, account: account, role: :administrator)

      get "/api/v2/accounts/#{account.id}/home/section", params: { name: 'leads' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to contain_exactly('granularity', 'buckets', 'leads', 'off_hours_leads', 'origins')
      expect(response.parsed_body['leads']['total']).to eq(1)
    end

    it 'answers an unknown section with unprocessable entity' do
      get "/api/v2/accounts/#{account.id}/home/section", params: { name: 'revenue' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
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
