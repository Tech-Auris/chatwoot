require 'rails_helper'

RSpec.describe 'Secretary confirmation send logs API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/secretary_confirmation_send_logs" }
  let(:reminder) { { calendar_id: 'cfeegow_prof12', event_id: '9876', reminder_type: '24h' } }

  it 'returns unauthorized without a token' do
    post url, params: reminder

    expect(response).to have_http_status(:unauthorized)
  end

  it 'logs a reminder once: only the first call is told to send' do
    post url, params: reminder, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq('send' => true)

    post url, params: reminder, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('send' => false)

    post url, params: reminder.merge(reminder_type: '2h'), headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('send' => true)
    expect(account.secretary_confirmation_send_logs.count).to eq(2)
  end

  it "lists the account's logs of the given events in the Supabase row shape" do
    log = create(:secretary_confirmation_send_log, account: account, event_id: 'abc')
    create(:secretary_confirmation_send_log, account: account, event_id: 'outro')
    create(:secretary_confirmation_send_log, event_id: 'abc')

    get url, params: { event_ids: 'abc,def' }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to contain_exactly(
      include('id' => log.id, 'chatwoot_account_id' => account.id, 'event_id' => 'abc', 'calendar_id' => log.calendar_id,
              'reminder_type' => '24h', 'sent_at' => be_present)
    )
  end
end
