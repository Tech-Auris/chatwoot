require 'rails_helper'

RSpec.describe 'Conversation appointments API', type: :request do
  let(:erp) { create(:erp_source) }
  let(:account) { create(:account, funnel_enabled: true, erp_source: erp) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/appointments" }

  it 'creates and lists the appointments without moving the stage' do
    patch url, params: { appointment: { external_id: 'ag_1', scheduled_for: '2026-11-12T14:30:00-03:00' } },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    get url, headers: admin.create_new_auth_token, as: :json
    payload = response.parsed_body['payload']
    expect(payload.size).to eq(1)
    expect(payload.first).to include('external_id' => 'ag_1', 'source_id' => erp.id, 'status' => 'scheduled')
  end

  it 'records the amount paid later through the attendance block' do
    patch url, params: { attendance: { external_id: 'ag_1', procedures: [{ name: 'Protocolo', amount_paid: 1200.5 }] } },
               headers: admin.create_new_auth_token, as: :json

    procedure = response.parsed_body['payload'].first['procedures'].first
    expect(procedure).to include('name' => 'Protocolo', 'amount_paid' => 1200.5)
  end

  it 'answers 422 without a block' do
    patch url, params: {}, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
