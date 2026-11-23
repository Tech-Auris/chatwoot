require 'rails_helper'

RSpec.describe 'Virtual clinic config API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/config" }

  it 'tells the administrator what is missing to turn the AI team on' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ai_team']).to include('visible' => true, 'chat_enabled' => false, 'chat_missing' => 'openai_key')
    members = response.parsed_body.dig('ai_team', 'members').map { |member| member.slice('persona', 'name') }
    expect(members).to eq([{ 'persona' => 'secretary', 'name' => 'Clara' }, { 'persona' => 'manager', 'name' => 'Helena' },
                           { 'persona' => 'marketing', 'name' => 'Luciano' }])
    expect(response.parsed_body['ai_team']).to include('daily_question_limit' => 60, 'can_manage_settings' => true)
  end

  it 'enables the AI team once the clinic has its OpenAI key' do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['ai_team']).to include('visible' => true, 'chat_enabled' => true, 'chat_missing' => nil)
  end

  it 'shows the AI team to agents, without talking to it or managing it' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['ai_team']).to include('visible' => true, 'chat_enabled' => false, 'chat_missing' => nil,
                                                       'manages_team' => false, 'can_edit_layout' => false)
    restricted = response.parsed_body.dig('ai_team', 'members').to_h { |member| member.values_at('persona', 'restricted') }
    expect(restricted).to eq('secretary' => false, 'manager' => true, 'marketing' => true)
  end

  it 'lists the decoration packs in season' do
    travel_to(Time.zone.local(2026, 11, 20, 12)) { get url, headers: admin.create_new_auth_token, as: :json }

    seasons = response.parsed_body.dig('ai_team', 'seasons')
    expect(seasons['active']).to eq([{ 'key' => 'christmas', 'folder' => '11_natal', 'accessory' => 'Accessory_20_Gorro_Natal', 'until' => '31/12' },
                                     { 'key' => 'party', 'folder' => '13_festa', 'until' => nil }])
    expect(seasons['folders']).to eq(%w[11_natal 12_halloween 13_festa])
  end

  it 'is refused when the account is not released' do
    account.update!(virtual_clinic_enabled: false)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
