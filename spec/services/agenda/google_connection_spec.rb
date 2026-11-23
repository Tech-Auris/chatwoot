require 'rails_helper'

RSpec.describe Agenda::GoogleConnection do
  let(:token_url) { described_class::TOKEN_URL }

  def stub_token(body, status: 200)
    stub_request(:post, token_url).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def connect(refresh_token: 'refresh-1')
    InstallationConfig.find_or_initialize_by(name: described_class::REFRESH_TOKEN).update!(value: refresh_token)
  end

  before do
    InstallationConfig.find_or_initialize_by(name: 'GOOGLE_OAUTH_CLIENT_ID').update!(value: 'client-1')
    InstallationConfig.find_or_initialize_by(name: 'GOOGLE_OAUTH_CLIENT_SECRET').update!(value: 'secret-1')
    GlobalConfig.clear_cache
  end

  it 'asks Google for offline, read-only calendar access' do
    url = described_class.authorize_url(redirect_uri: 'https://app.example.com/callback', state: 'abc')

    query = Rack::Utils.parse_query(URI.parse(url).query)
    expect(query).to include('client_id' => 'client-1', 'state' => 'abc', 'access_type' => 'offline', 'prompt' => 'consent')
    expect(query['scope']).to include('calendar.readonly')
  end

  it 'keeps the refresh token and the e-mail of the account that authorized' do
    stub_token({ access_token: 'access-1', refresh_token: 'refresh-1' })
    stub_request(:get, described_class::USERINFO_URL).with(headers: { 'Authorization' => 'Bearer access-1' })
                                                     .to_return(body: { email: 'agenda@example.com' }.to_json,
                                                                headers: { 'Content-Type' => 'application/json' })

    described_class.connect!(code: 'code-1', redirect_uri: 'https://app.example.com/callback')

    expect(described_class).to be_connected
    expect(described_class.email).to eq('agenda@example.com')
    expect(a_request(:post, token_url).with(body: hash_including('code' => 'code-1', 'grant_type' => 'authorization_code'))).to have_been_made
  end

  it 'refuses a connection that brings no refresh token' do
    stub_token({ access_token: 'access-1' })

    expect { described_class.connect!(code: 'code-1', redirect_uri: 'https://app.example.com/callback') }
      .to raise_error(described_class::Error, I18n.t('agenda.errors.google_no_refresh_token'))
    expect(described_class).not_to be_connected
  end

  it 'caches the access token it gets with the refresh token' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    connect
    stub_token({ access_token: 'access-2', expires_in: 3599 })

    2.times { expect(described_class.access_token).to eq('access-2') }
    expect(a_request(:post, token_url).with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'refresh-1')))
      .to have_been_made.once
  end

  it 'asks to reconnect when Google no longer accepts the refresh token' do
    connect
    stub_token({ error: 'invalid_grant' }, status: 400)

    expect { described_class.access_token }.to raise_error(described_class::Error, I18n.t('agenda.errors.google_expired'))
  end

  it 'says so when no account is connected' do
    expect { described_class.access_token }.to raise_error(described_class::Error, I18n.t('agenda.errors.google_not_connected'))
  end

  it 'forgets the account on disconnect' do
    connect
    described_class.disconnect!

    expect(described_class).not_to be_connected
  end
end
