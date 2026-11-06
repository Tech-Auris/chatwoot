require 'rails_helper'

RSpec.describe 'Mentions API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:author) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET /api/v1/accounts/{account.id}/mentions/unseen' do
    it 'returns unauthorized for an unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/mentions/unseen"

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when it is an authenticated user' do
      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'returns only the unseen mentions of the current user' do
        create(:mention, user: agent, conversation: conversation, mentioned_by: author, seen_at: nil)
        create(:mention, user: agent, conversation: create(:conversation, account: account, inbox: inbox), seen_at: Time.current)
        create(:mention, user: author, conversation: conversation, seen_at: nil)

        get "/api/v1/accounts/#{account.id}/mentions/unseen", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['conversation_id']).to eq(conversation.display_id)
        expect(payload.first['mentioned_by']['name']).to eq(author.available_name)
      end

      it 'skips conversations from inboxes the user cannot access' do
        other_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account))
        create(:mention, user: agent, conversation: other_conversation, seen_at: nil)

        get "/api/v1/accounts/#{account.id}/mentions/unseen", headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['payload']).to be_empty
      end
    end
  end
end
