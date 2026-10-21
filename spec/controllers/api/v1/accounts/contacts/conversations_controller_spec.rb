require 'rails_helper'

RSpec.describe '/api/v1/accounts/{account.id}/contacts/:id/conversations', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox_1) { create(:inbox, account: account) }
  let(:inbox_2) { create(:inbox, account: account) }
  let(:contact_inbox_1) { create(:contact_inbox, contact: contact, inbox: inbox_1) }
  let(:contact_inbox_2) { create(:contact_inbox, contact: contact, inbox: inbox_2) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:unknown) { create(:user, account: account, role: nil) }

  before do
    create(:inbox_member, user: agent, inbox: inbox_1)
    2.times.each do
      create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1)
      create(:conversation, account: account, inbox: inbox_2, contact: contact, contact_inbox: contact_inbox_2)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/conversations' do
    context 'when unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is logged in' do
      context 'with user as administrator' do
        it 'returns conversations from all inboxes' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: admin.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 4
        end
      end

      context 'with the order and the pages' do
        it 'lists the newest created first, even when an older one had the latest activity' do
          oldest = create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1,
                                         created_at: 1.year.ago, last_activity_at: 1.minute.ago)

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: admin.create_new_auth_token

          ids = response.parsed_body['payload'].pluck('id')
          expect(ids.last).to eq(oldest.display_id)
          expect(ids).to eq(contact.conversations.order(created_at: :desc, id: :desc).map(&:display_id))
        end

        it 'pages the list, telling when there are more' do
          stub_const('Api::V1::Accounts::Contacts::ConversationsController::PER_PAGE', 3)

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: admin.create_new_auth_token
          expect(response.parsed_body['payload'].length).to eq 3
          expect(response.parsed_body['meta']['has_more']).to be true

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", params: { page: 2 }, headers: admin.create_new_auth_token
          expect(response.parsed_body['payload'].length).to eq 1
          expect(response.parsed_body['meta']['has_more']).to be false
        end
      end

      context 'with user as agent' do
        it 'returns conversations from the inboxes which agent has access to' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: agent.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 2
        end
      end

      context 'with user as unknown role' do
        it 'returns conversations from no inboxes' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: unknown.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 0
        end
      end
    end
  end
end
