require 'rails_helper'

RSpec.describe 'POST /api/v1/accounts/:account_id/contacts/:id/ai_status', type: :request do
  let(:account) { create(:account, ai_status_uses_attribute: true) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Ana') }

  def toggle(user, enabled)
    post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/ai_status",
         params: { enabled: enabled }, headers: user.create_new_auth_token, as: :json
  end

  it 'lets an agent turn the AI off for the contact, naming who did it' do
    toggle(agent, false)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload']).to include('ai_disabled' => true, 'ai_disabled_by_name' => 'Ana')
    expect(response.parsed_body['payload']['ai_disabled_at']).to be_present
  end

  it 'lets an agent turn it back on' do
    contact.disable_ai!(agent)

    toggle(agent, true)

    expect(response).to have_http_status(:success)
    expect(contact.reload.ai_disabled).to be(false)
  end

  it 'refuses a user from another account' do
    toggle(create(:user), false)

    expect(response).to have_http_status(:unauthorized)
    expect(contact.reload.ai_disabled).to be(false)
  end
end
