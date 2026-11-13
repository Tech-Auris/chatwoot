require 'rails_helper'

RSpec.describe 'Assignable Agents API', type: :request do
  let(:account) { create(:account) }
  let(:agent1) { create(:user, account: account, role: :agent) }
  let!(:agent2) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/assignable_agents' do
    let(:inbox1) { create(:inbox, account: account) }
    let(:inbox2) { create(:inbox, account: account) }

    before do
      create(:inbox_member, user: agent1, inbox: inbox1)
      create(:inbox_member, user: agent1, inbox: inbox2)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/assignable_agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is not part of an inbox' do
      context 'when the user is an admininstrator' do
        it 'returns the assignable inbox members without administrators' do
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: [inbox1.id, inbox2.id] },
              headers: admin.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
          expect(response_data.pluck(:id)).to contain_exactly(agent1.id)
        end
      end

      context 'when the user is an agent' do
        it 'returns unauthorized' do
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: [inbox1.id, inbox2.id] },
              headers: agent2.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when the user is part of the inbox' do
      it 'returns the assignable inbox members without administrators' do
        get "/api/v1/accounts/#{account.id}/assignable_agents",
            params: { inbox_ids: [inbox1.id, inbox2.id] },
            headers: agent1.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
        expect(response_data.pluck(:id)).to contain_exactly(agent1.id)
      end
    end

    context 'when the AI user is an administrator' do
      before do
        InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: admin.id.to_s, locked: false)
        GlobalConfig.clear_cache
      end

      it 'keeps it in the list' do
        get "/api/v1/accounts/#{account.id}/assignable_agents",
            params: { inbox_ids: [inbox1.id] },
            headers: admin.create_new_auth_token,
            as: :json

        response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
        expect(response_data.pluck(:id)).to contain_exactly(agent1.id, admin.id)
        expect(response_data.find { |agent| agent[:id] == admin.id }[:is_ai_user]).to be true
      end
    end

    # Managers can be assigned to any conversation in the account (User#assigned_inboxes
    # returns every inbox for the manager role), so they must show up in the assignable
    # pool even for inboxes they are not explicit members of.
    context 'when a manager is not part of any queried inbox' do
      let!(:manager) { create(:user, account: account, role: :manager) }

      it 'still returns the manager alongside the members' do
        get "/api/v1/accounts/#{account.id}/assignable_agents",
            params: { inbox_ids: [inbox1.id, inbox2.id] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
        expect(response_data.pluck(:id)).to include(manager.id)
        expect(response_data.pluck(:role)).to include('manager')
      end
    end
  end
end
