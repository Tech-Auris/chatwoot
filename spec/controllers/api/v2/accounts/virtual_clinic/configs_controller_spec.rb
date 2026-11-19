require 'rails_helper'

RSpec.describe 'Virtual clinic config API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/config" }

  it 'tells the administrator what is missing to turn the AI team on' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ai_team']).to include('visible' => true, 'enabled' => false, 'missing' => 'openai_key')
    members = response.parsed_body.dig('ai_team', 'members').map { |member| member.slice('persona', 'name') }
    expect(members).to eq([{ 'persona' => 'secretary', 'name' => 'Clara' }, { 'persona' => 'manager', 'name' => 'Helena' }])
    expect(response.parsed_body['ai_team']).to include('daily_question_limit' => 60, 'can_manage_settings' => true)
  end

  it 'enables the AI team once the clinic has its OpenAI key' do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['ai_team']).to include('visible' => true, 'enabled' => true, 'missing' => nil)
  end

  it 'hides the AI team from agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['ai_team']).to include('visible' => false, 'enabled' => false, 'missing' => nil, 'members' => [])
  end

  it 'is refused when the account is not released' do
    account.update!(virtual_clinic_enabled: false)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
