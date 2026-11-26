require 'rails_helper'

RSpec.describe 'Message failure reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'Ananindeua') }
  let(:other_inbox) { create(:inbox, account: account, name: 'Belém') }
  let(:url) { "/api/v2/accounts/#{account.id}/message_failure_reports" }
  let(:payment_error) { '131042: Business eligibility payment issue' }

  def failed_message(inbox:, error:, conversation: create(:conversation, account: account, inbox: inbox), **attributes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     status: :failed, external_error: error, **attributes)
  end

  it 'is refused to agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'groups the failures by inbox and error, busiest first, with the latest conversations' do
    conversations = create_list(:conversation, 6, account: account, inbox: inbox)
    conversations.each_with_index do |conversation, index|
      failed_message(inbox: inbox, error: payment_error, conversation: conversation, created_at: (10 - index).hours.ago)
    end
    failed_message(inbox: inbox, error: payment_error, conversation: conversations.first, created_at: 1.hour.ago)
    failed_message(inbox: other_inbox, error: 'Recipient is not a valid WhatsApp user')

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body).to include('period' => '7d', 'total' => 8)
    expect(body['inboxes'].pluck('inbox_name')).to eq(%w[Ananindeua Belém])
    reason = body['inboxes'].first['reasons'].sole
    expect(reason).to include('error' => payment_error, 'count' => 7)
    expect(reason['conversation_ids']).to eq([conversations.first, *conversations.last(4).reverse].map(&:display_id))
    expect(reason['last_at']).to be_within(5).of(1.hour.ago.to_i)
  end

  it 'leaves out received, delivered, old and other accounts\' messages' do
    conversation = create(:conversation, account: account, inbox: inbox)
    failed_message(inbox: inbox, error: payment_error, conversation: conversation)
    failed_message(inbox: inbox, error: payment_error, conversation: conversation, message_type: :incoming)
    failed_message(inbox: inbox, error: payment_error, conversation: conversation, created_at: 8.days.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, status: :delivered)
    other_inbox = create(:inbox)
    other_conversation = create(:conversation, inbox: other_inbox, account: other_inbox.account)
    create(:message, account: other_inbox.account, inbox: other_inbox, conversation: other_conversation,
                     message_type: :outgoing, status: :failed, external_error: payment_error)

    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['total']).to eq(1)

    get url, params: { period: '30d' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['total']).to eq(2)
  end

  it 'filters by inbox and by part of the error' do
    failed_message(inbox: inbox, error: payment_error)
    failed_message(inbox: other_inbox, error: '(#131030) Recipient phone number not in allowed list')

    get url, params: { inbox_id: other_inbox.id }, headers: admin.create_new_auth_token
    expect(response.parsed_body['inboxes'].pluck('inbox_name')).to eq(['Belém'])

    get url, params: { error: '131042' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['inboxes'].flat_map { |row| row['reasons'].pluck('error') }).to eq([payment_error])
  end
end
