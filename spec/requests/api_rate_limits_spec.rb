require 'rails_helper'

RSpec.describe 'API rate limits', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:headers) { { api_access_token: agent.access_token.token } }
  let(:messages_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }

  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = original_store
    ApiRateLimits.reset!
  end

  def configure(name, value)
    InstallationConfig.where(name: name).first_or_create!(value: value, locked: false).update!(value: value)
    ApiRateLimits.reset!
  end

  def send_message(ip)
    post messages_path, params: { content: 'Olá' }, headers: headers, env: { 'REMOTE_ADDR' => ip }, as: :json
  end

  it 'stops messages sent through the API on one inbox above the limit' do
    configure('API_RATE_LIMIT_MESSAGES_PER_INBOX', '2')

    2.times { send_message('203.0.113.5') }
    expect(response).to have_http_status(:ok)

    send_message('203.0.113.5')
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'stops a token that spreads its requests over many IPs' do
    configure('API_RATE_LIMIT_PER_TOKEN', '2')

    get "/api/v1/accounts/#{account.id}/inboxes", headers: headers, env: { 'REMOTE_ADDR' => '203.0.113.5' }
    get "/api/v1/accounts/#{account.id}/inboxes", headers: headers, env: { 'REMOTE_ADDR' => '203.0.113.6' }
    get "/api/v1/accounts/#{account.id}/inboxes", headers: headers, env: { 'REMOTE_ADDR' => '203.0.113.7' }

    expect(response).to have_http_status(:too_many_requests)
  end

  it 'lets internal IPs through every limit' do
    configure('API_RATE_LIMIT_MESSAGES_PER_INBOX', '1')
    configure('API_INTERNAL_IPS', '100.62.125.0/24')

    3.times { send_message('100.62.125.9') }

    expect(response).to have_http_status(:ok)
  end
end
