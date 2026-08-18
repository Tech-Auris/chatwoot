require 'rails_helper'

RSpec.describe 'Canned Responses API', type: :request do
  let(:account) { create(:account) }

  before do
    create(:canned_response, account: account, content: 'Hey {{ contact.name }}, Thanks for reaching out', short_code: 'name-short-code')
  end

  describe 'GET /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all the canned responses' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq(account.canned_responses.as_json)
      end

      it 'returns all the canned responses the user searched for' do
        cr1 = account.canned_responses.first
        create(:canned_response, account: account, content: 'Great! Looking forward', short_code: 'short-code')
        cr2 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'content-with-thanks')
        cr3 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'Thanks')

        params = { search: 'thanks' }

        get "/api/v1/accounts/#{account.id}/canned_responses",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq(
          [cr3, cr2, cr1].as_json
        )
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/canned_responses with an inbox' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:inbox) { create(:inbox, account: account) }
    let(:other_inbox) { create(:inbox, account: account) }

    # An agent typing "/" inside a conversation must not be offered a response
    # written for a different inbox.
    it 'returns the global responses plus the ones of that inbox' do
      global = create(:canned_response, account: account, short_code: 'global')
      mine = create(:canned_response, account: account, inbox: inbox, short_code: 'mine')
      theirs = create(:canned_response, account: account, inbox: other_inbox, short_code: 'theirs')

      get "/api/v1/accounts/#{account.id}/canned_responses",
          params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token

      returned = response.parsed_body.pluck('id')
      expect(returned).to include(global.id, mine.id)
      expect(returned).not_to include(theirs.id)
    end

    it 'lists every response when no inbox is given, as the settings screen does' do
      create(:canned_response, account: account, short_code: 'global')
      create(:canned_response, account: account, inbox: inbox, short_code: 'mine')

      get "/api/v1/accounts/#{account.id}/canned_responses", headers: agent.create_new_auth_token

      # Plus the one the outer setup already created.
      expect(response.parsed_body.size).to eq(3)
    end

    it 'keeps the inbox filter while searching' do
      create(:canned_response, account: account, inbox: other_inbox, short_code: 'promo')
      mine = create(:canned_response, account: account, inbox: inbox, short_code: 'promocao')

      get "/api/v1/accounts/#{account.id}/canned_responses",
          params: { inbox_id: inbox.id, search: 'promo' }, headers: agent.create_new_auth_token

      expect(response.parsed_body.pluck('id')).to eq([mine.id])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'creates a new canned response' do
        params = { short_code: 'short', content: 'content' }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.count).to eq(2)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'updates an existing canned response' do
        params = { short_code: 'B' }

        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(canned_response.reload.short_code).to eq('B')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'destroys the canned response' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(CannedResponse.count).to eq(0)
      end
    end
  end
end
