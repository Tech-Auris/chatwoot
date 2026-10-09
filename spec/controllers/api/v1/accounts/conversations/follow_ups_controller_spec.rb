require 'rails_helper'

RSpec.describe 'Follow-ups API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def follow_ups_url
    api_v1_account_conversation_follow_ups_url(account_id: account.id, conversation_id: conversation.display_id)
  end

  def follow_up_url(id)
    api_v1_account_conversation_follow_up_url(account_id: account.id, conversation_id: conversation.display_id, id: id)
  end

  it 'returns unauthorized for unauthenticated users' do
    get follow_ups_url
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'POST #create' do
    it 'starts a FUP on the conversation' do
      post follow_ups_url, params: { run_id: '1785283326516', step: 1, delay_minutes: 240 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      follow_up = conversation.follow_ups.last
      expect(follow_up).to have_attributes(step: 1, delay_minutes: 240, inbox: inbox, delivery_status: 'pending', outcome: 'waiting')
      expect(response.parsed_body).to include('id' => follow_up.id, 'conversation_id' => conversation.display_id)
    end

    it 'marks the FUP still waiting as unanswered' do
      previous = create(:follow_up, conversation: conversation, delivery_status: :sent)

      post follow_ups_url, params: { run_id: previous.run_id, step: 2, delay_minutes: 480 }, headers: admin.create_new_auth_token, as: :json

      expect(previous.reload.outcome).to eq('no_response')
      expect(previous.outcome_at).to be_present
    end

    it 'refuses a sixth FUP' do
      post follow_ups_url, params: { run_id: 'x', step: 6, delay_minutes: 60 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses the same step twice in a run' do
      create(:follow_up, conversation: conversation, run_id: 'x', step: 1)

      post follow_ups_url, params: { run_id: 'x', step: 1, delay_minutes: 60 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is not open to agents' do
      create(:inbox_member, inbox: inbox, user: agent)

      post follow_ups_url, params: { run_id: 'x', step: 1, delay_minutes: 60 }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH #update' do
    let!(:follow_up) { create(:follow_up, conversation: conversation) }

    it 'records that the message went out' do
      patch follow_up_url(follow_up.id), params: { delivery_status: 'sent' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(follow_up.reload.delivery_status).to eq('sent')
      expect(follow_up.processed_at).to be_present
    end

    it 'records a failed send with the reason' do
      patch follow_up_url(follow_up.id), params: { delivery_status: 'failed', error_message: 'Template not found' },
                                         headers: admin.create_new_auth_token, as: :json

      expect(follow_up.reload).to have_attributes(delivery_status: 'failed', error_message: 'Template not found')
    end

    it 'updates the latest FUP of the conversation without its id' do
      latest = create(:follow_up, conversation: conversation, step: 2)

      patch follow_up_url('latest'), params: { outcome: 'reengaged' }, headers: admin.create_new_auth_token, as: :json

      expect(latest.reload.outcome).to eq('reengaged')
      expect(latest.outcome_at).to be_present
      expect(follow_up.reload.outcome).to eq('waiting')
    end

    it 'refuses an unknown outcome' do
      patch follow_up_url(follow_up.id), params: { outcome: 'maybe' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET #index' do
    it 'lists the FUPs of the conversation, optionally of one run' do
      first = create(:follow_up, conversation: conversation, run_id: 'a')
      create(:follow_up, conversation: conversation, run_id: 'b')
      create(:inbox_member, inbox: inbox, user: agent)

      get follow_ups_url, params: { run_id: 'a' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([first.id])
    end
  end
end
