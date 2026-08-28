require 'rails_helper'

RSpec.describe 'Funnel stage on the conversation', type: :request do
  let(:account) { create(:account, funnel_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:stage) { create(:funnel_stage, name: 'Em Qualificação', color: '#2563EB') }

  before { create(:inbox_member, user: admin, inbox: inbox) }

  describe 'GET /api/v1/accounts/{account.id}/conversations' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox, funnel_stage: stage) }

    # The header renders the stage from the conversation payload; without this
    # every conversation opened would cost an extra request just to learn it.
    it 'serializes the stage with the colour the badge paints' do
      get "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token

      payload = response.parsed_body['data']['payload'].find { |row| row['id'] == conversation.display_id }
      expect(payload['funnel_stage']).to include('id' => stage.id, 'name' => 'Em Qualificação', 'color' => '#2563EB')
    end

    it 'omits the stage for an account that does not use the funnel' do
      account.update!(funnel_enabled: false)

      get "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token

      payload = response.parsed_body['data']['payload'].find { |row| row['id'] == conversation.display_id }
      expect(payload).not_to have_key('funnel_stage')
    end

    it 'omits the stage when the conversation is not in one' do
      conversation.update!(funnel_stage: nil)

      get "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token

      payload = response.parsed_body['data']['payload'].find { |row| row['id'] == conversation.display_id }
      expect(payload).not_to have_key('funnel_stage')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/funnel/move' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'moves the conversation using the stage id sent by the header' do
      post "/api/v1/accounts/#{account.id}/funnel/move",
           params: { conversation_id: conversation.display_id, funnel_stage_id: stage.id },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(conversation.reload.funnel_stage).to eq(stage)
    end

    it 'still accepts the stage name the kanban sends' do
      post "/api/v1/accounts/#{account.id}/funnel/move",
           params: { conversation_id: conversation.display_id, stage: 'Em Qualificação' },
           headers: admin.create_new_auth_token

      expect(conversation.reload.funnel_stage).to eq(stage)
    end

    it 'explains itself when neither handle is sent' do
      post "/api/v1/accounts/#{account.id}/funnel/move",
           params: { conversation_id: conversation.display_id },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('etapa de destino')
    end
  end
end
