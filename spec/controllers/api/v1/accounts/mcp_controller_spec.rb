require 'rails_helper'

RSpec.describe 'Account MCP API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/mcp" }

  it 'turns the MCP on for an administrator who accepts the term' do
    patch url, params: { enabled: true, terms_accepted: true }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(account.reload).to have_attributes(mcp_enabled: true, mcp_enabled_by: admin)
    expect(account.mcp_enabled_at).to be_present
    expect(response.parsed_body).to include('mcp_enabled' => true, 'mcp_enabled_by_name' => admin.name)
  end

  it 'refuses to turn it on without the term' do
    patch url, params: { enabled: true }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.mcp_enabled).to be(false)
  end

  it 'turns it off and forgets who accepted the term' do
    account.enable_mcp!(admin)

    patch url, params: { enabled: false }, headers: admin.create_new_auth_token, as: :json

    expect(account.reload).to have_attributes(mcp_enabled: false, mcp_enabled_at: nil, mcp_enabled_by: nil)
  end

  it 'refuses managers and agents' do
    manager = create(:user, account: account)
    manager.account_users.find_by(account: account).update!(role: :manager)
    agent = create(:user, account: account, role: :agent)

    [manager, agent].each do |user|
      patch url, params: { enabled: true, terms_accepted: true }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
    expect(account.reload.mcp_enabled).to be(false)
  end

  it 'exposes the switch per account in the profile, which the MCP reads' do
    account.enable_mcp!(admin)

    get '/api/v1/profile', headers: { api_access_token: admin.access_token.token }, as: :json

    expect(response.parsed_body['accounts'].first).to include('id' => account.id, 'mcp_enabled' => true)
  end
end
