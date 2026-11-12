require 'rails_helper'

RSpec.describe 'Webhooks API access by role', type: :request do
  let(:account) { create(:account) }
  let(:url) { "/api/v1/accounts/#{account.id}/webhooks" }
  let(:params) { { webhook: { name: 'CRM', url: 'https://crm.example.com/hook', subscriptions: ['message_created'] } } }

  it 'lets a manager list and create webhooks' do
    manager = create(:user, account: account)
    manager.account_users.find_by(account: account).update!(role: :manager)

    post url, params: params, headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    get url, headers: manager.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['webhooks'].pluck('url')).to eq(['https://crm.example.com/hook'])
  end

  it 'refuses agents' do
    agent = create(:user, account: account, role: :agent)

    post url, params: params, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
