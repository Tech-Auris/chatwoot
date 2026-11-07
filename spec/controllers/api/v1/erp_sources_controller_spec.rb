require 'rails_helper'

RSpec.describe 'ERP sources API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/erp_sources' do
    it 'returns unauthorized without a token' do
      get '/api/v1/erp_sources'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists the active ERPs with their Supabase ids' do
      create(:erp_source, id: 2, name: 'Feegow')
      create(:erp_source, id: 1, name: 'Google Calendar')
      create(:erp_source, id: 5, name: 'MedWare', active: false)

      get '/api/v1/erp_sources', headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq([{ 'id' => 1, 'name' => 'Google Calendar' }, { 'id' => 2, 'name' => 'Feegow' }])
    end
  end
end
