require 'rails_helper'

RSpec.describe 'Follow-up reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Mariana Souza', phone_number: '+5521998124410') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:quiet_conversation) { create(:conversation, account: account, inbox: other_inbox) }
  let(:url) { "/api/v2/accounts/#{account.id}/follow_up_reports" }
  let(:range) { { from: 1.day.ago.to_i, to: 1.minute.from_now.to_i } }

  before do
    create(:follow_up, conversation: conversation, run_id: 'a', step: 1, delay_minutes: 240, delivery_status: :sent, outcome: :no_response)
    create(:follow_up, conversation: conversation, run_id: 'a', step: 2, delay_minutes: 480, delivery_status: :sent, outcome: :reengaged)
    create(:follow_up, conversation: quiet_conversation, run_id: 'b', step: 1, delay_minutes: 240, delivery_status: :failed,
                       error_message: 'Template not found')
  end

  it 'is refused to agents' do
    get url, params: range, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the totals, the FUPs newest first and the reengagement by FUP number' do
    get url, params: range, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['totals']).to eq('total_conversations' => 2, 'conversations_with_follow_up' => 2, 'reengaged_conversations' => 1)
    expect(body['rows'].first).to include('step' => 1, 'delivery_status' => 'failed', 'error_message' => 'Template not found')
    expect(body['rows'].pluck('conversation_id')).to include(conversation.display_id)
    expect(body['steps']).to eq([
                                  { 'step' => 1, 'delay_minutes' => 240, 'sent' => 1, 'reengaged' => 0 },
                                  { 'step' => 2, 'delay_minutes' => 480, 'sent' => 1, 'reengaged' => 1 }
                                ])
    expect(body['meta']).to include('total_count' => 3)
  end

  it 'filters by inbox and by contact name or phone' do
    get url, params: range.merge(inbox_id: other_inbox.id), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].size).to eq(1)

    get url, params: range.merge(q: '99812-4410'), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].pluck('contact_name')).to all(eq('Mariana Souza'))
    expect(response.parsed_body['rows'].size).to eq(2)
  end

  it 'filters by delivery and by result' do
    get url, params: range.merge(delivery_status: 'failed'), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].pluck('error_message')).to eq(['Template not found'])

    get url, params: range.merge(outcome: 'reengaged'), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].pluck('step')).to eq([2])
  end

  it 'filters by the hour the FUP was sent, in Brasília time' do
    FollowUp.update_all(created_at: Time.zone.parse('2026-10-08 13:30 -03:00')) # rubocop:disable Rails/SkipsModelValidations
    window = { from: Time.zone.parse('2026-10-08 00:00 -03:00').to_i, to: Time.zone.parse('2026-10-08 23:59 -03:00').to_i }

    get url, params: window.merge(hour_from: 13, hour_to: 13), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].size).to eq(3)

    get url, params: window.merge(hour_from: 14), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows']).to be_empty
  end

  it 'exports the FUPs as CSV' do
    get "#{url}.csv", params: range, headers: admin.create_new_auth_token

    expect(response.media_type).to eq('text/csv')
    lines = CSV.parse(response.body)
    expect(lines.first).to include('Data/hora', 'FUP', 'Resultado')
    expect(lines.size).to eq(4)
  end
end
