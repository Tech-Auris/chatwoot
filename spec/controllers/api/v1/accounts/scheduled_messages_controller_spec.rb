require 'rails_helper'

RSpec.describe 'Scheduled Messages API', type: :request do
  let(:account) { create(:account) }
  let!(:pending_in_a) { scheduled(inbox_a, status: :pending, content: 'sm-a', scheduled_at: 2.hours.from_now) }
  let!(:pending_in_b) { scheduled(inbox_b, status: :pending, content: 'sm-b', scheduled_at: 3.hours.from_now) }
  let!(:sent_in_a) { scheduled(inbox_a, status: :sent, content: 'sm-a-sent', scheduled_at: 1.day.ago) }
  # Auto-assignment off — creating conversations by the dozen fans out to
  # Redis round-robin work that has nothing to do with the panel.
  let(:inbox_a) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:inbox_b) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    create(:inbox_member, user: agent, inbox: inbox_a)
  end

  describe 'GET /api/v1/accounts/:account_id/scheduled_messages' do
    it 'refuses an unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/scheduled_messages"

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when the current user is an administrator' do
      it 'lists pending scheduled messages from every inbox by default' do
        get "/api/v1/accounts/#{account.id}/scheduled_messages",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to contain_exactly(pending_in_a.id, pending_in_b.id)
        expect(response.parsed_body['meta']).to include('status' => 'pending')
      end
    end

    context 'when the current user is a manager' do
      it 'lists sent scheduled messages across every inbox on request' do
        get "/api/v1/accounts/#{account.id}/scheduled_messages?status=sent",
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to eq([sent_in_a.id])
      end
    end

    context 'when the current user is an agent' do
      it 'lists only scheduled messages that live in an inbox the agent belongs to' do
        get "/api/v1/accounts/#{account.id}/scheduled_messages",
            headers: agent.create_new_auth_token,
            as: :json

        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to eq([pending_in_a.id])
      end
    end

    it 'ships the contact and inbox summary alongside each row so the panel can render them without a follow-up call' do
      get "/api/v1/accounts/#{account.id}/scheduled_messages",
          headers: admin.create_new_auth_token,
          as: :json

      row = response.parsed_body['items'].find { |i| i['id'] == pending_in_a.id }
      expect(row).to include(
        'status' => 'pending',
        'content' => 'sm-a',
        'conversation_id' => pending_in_a.conversation.display_id
      )
      expect(row['inbox']).to include('id' => inbox_a.id, 'name' => inbox_a.name)
      expect(row['contact']).to include('id' => pending_in_a.conversation.contact.id)
    end

    it 'falls back to the default status when an unknown filter is passed' do
      get "/api/v1/accounts/#{account.id}/scheduled_messages?status=whatever",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['meta']['status']).to eq('pending')
    end

    it 'paginates so the panel can scroll for older ones' do
      30.times { scheduled(inbox_a, status: :pending, content: 'p', scheduled_at: (rand(10..500)).minutes.from_now) }

      get "/api/v1/accounts/#{account.id}/scheduled_messages?page=2",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['meta']['current_page']).to eq(2)
      expect(response.parsed_body['meta']['total_pages']).to be >= 2
    end
  end

  describe 'POST /api/v1/accounts/:account_id/scheduled_messages' do
    let(:target_contact) { create(:contact, account: account, phone_number: '+5511900099999') }

    it 'creates the scheduled message on an existing open conversation for the (contact, inbox) pair' do
      contact_inbox = create(:contact_inbox, contact: target_contact, inbox: inbox_a, source_id: target_contact.phone_number)
      conversation = create(:conversation, account: account, inbox: inbox_a, contact: target_contact, contact_inbox: contact_inbox, status: :open)

      expect do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               contact_id: target_contact.id,
               inbox_id: inbox_a.id,
               content: 'Retomando amanhã',
               scheduled_at: 6.hours.from_now.iso8601,
               hold_on_reply: true
             },
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(ScheduledMessage, :count).by(1).and(not_change(Conversation, :count))

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.display_id)
      sm = ScheduledMessage.last
      expect(sm).to have_attributes(content: 'Retomando amanhã', conversation_id: conversation.id, hold_on_reply: true, status: 'pending')
    end

    it 'creates a fresh conversation when the contact has no open thread on that inbox yet' do
      expect do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               contact_id: target_contact.id,
               inbox_id: inbox_a.id,
               content: 'Follow-up amanhã',
               scheduled_at: 3.hours.from_now.iso8601
             },
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(ScheduledMessage, :count).by(1).and(change(Conversation, :count).by(1))

      expect(response).to have_http_status(:success)
    end

    it 'refuses when the current user is not a member of the requested inbox' do
      expect do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               contact_id: target_contact.id,
               inbox_id: inbox_b.id,
               content: 'Fora do escopo',
               scheduled_at: 1.day.from_now.iso8601
             },
             headers: agent.create_new_auth_token,
             as: :json
      end.not_to change(ScheduledMessage, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses when the contact does not belong to the account' do
      other_contact = create(:contact, account: create(:account))

      post "/api/v1/accounts/#{account.id}/scheduled_messages",
           params: {
             contact_id: other_contact.id,
             inbox_id: inbox_a.id,
             content: 'x',
             scheduled_at: 1.day.from_now.iso8601
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/scheduled_messages/:id' do
    it 'cancels a pending scheduled message the current user can see' do
      expect do
        delete "/api/v1/accounts/#{account.id}/scheduled_messages/#{pending_in_a.id}",
               headers: admin.create_new_auth_token,
               as: :json
      end.to change { ScheduledMessage.where(id: pending_in_a.id).count }.from(1).to(0)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['deleted']).to eq(1)
    end

    it 'answers 404 for an agent trying to cancel a scheduled message from an inbox they do not belong to' do
      expect do
        delete "/api/v1/accounts/#{account.id}/scheduled_messages/#{pending_in_b.id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(ScheduledMessage, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses to cancel a sent scheduled message — those are terminal' do
      delete "/api/v1/accounts/#{account.id}/scheduled_messages/#{sent_in_a.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ScheduledMessage.exists?(sent_in_a.id)).to be true
    end
  end

  def scheduled(inbox, status:, content:, scheduled_at:)
    conversation = create(:conversation, account: account, inbox: inbox)
    # The model requires a future `scheduled_at` on create and refuses
    # `sent`/`failed`/`held` on create — the state machine wants every row
    # to start as pending in the future. The seed builds that legal shape,
    # then updates the columns directly to the state the test wants.
    sm = ScheduledMessage.create!(
      account: account,
      conversation: conversation,
      inbox: inbox,
      author: admin,
      content: content,
      status: :pending,
      scheduled_at: 1.hour.from_now
    )
    updates = {}
    updates[:scheduled_at] = scheduled_at if scheduled_at != 1.hour.from_now
    updates[:status] = ScheduledMessage.statuses[status.to_s] unless status == :pending
    sm.update_columns(updates) if updates.any? # rubocop:disable Rails/SkipsModelValidations
    sm.reload
  end
end
