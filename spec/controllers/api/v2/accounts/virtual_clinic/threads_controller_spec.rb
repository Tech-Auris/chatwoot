require 'rails_helper'

RSpec.describe 'Virtual clinic threads API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/threads/secretary" }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account)
  end

  it 'opens the conversation with the persona' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['persona']).to include('persona' => 'secretary', 'name' => 'Clara')
    expect(response.parsed_body['messages']).to eq([])
  end

  it 'stores the question, a pending answer and queues the AI' do
    expect do
      post "#{url}/messages", params: { content: 'Quem você está atendendo agora?' }, headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(VirtualClinic::AnswerJob)

    roles = response.parsed_body['messages'].map { |message| message.values_at('role', 'status') }
    expect(roles).to eq([%w[user done], %w[assistant pending]])
  end

  it 'refuses questions over the daily limit the clinic set' do
    account.update!(settings: account.settings.merge(VirtualClinic::QuestionLimit::SETTING => 1))
    2.times { post "#{url}/messages", params: { content: 'Oi' }, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:too_many_requests)
  end

  it 'starts a new conversation on reset' do
    get url, headers: admin.create_new_auth_token, as: :json
    first_thread = response.parsed_body['thread_id']

    post "#{url}/reset", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['thread_id']).not_to eq(first_thread)
  end

  it 'is refused to agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lets only the administrator change the daily limit' do
    settings_url = "/api/v2/accounts/#{account.id}/virtual_clinic/settings"
    patch settings_url, params: { daily_question_limit: 100 }, headers: admin.create_new_auth_token, as: :json
    expect(account.reload.settings[VirtualClinic::QuestionLimit::SETTING]).to eq(100)

    patch settings_url, params: { daily_question_limit: '' }, headers: admin.create_new_auth_token, as: :json
    expect(VirtualClinic::QuestionLimit.for(account.reload)).to be_nil
  end
end
