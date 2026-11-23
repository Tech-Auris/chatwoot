require 'rails_helper'

RSpec.describe 'Super Admin agenda Google connection', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:callback) { '/super_admin/integrations/agenda_google/callback' }

  before do
    sign_in(super_admin, scope: :super_admin)
    allow(Agenda::GoogleConnection).to receive(:configured?).and_return(true)
  end

  def start_connection
    post '/super_admin/integrations/agenda_google/connect'
    Rack::Utils.parse_query(URI.parse(response.location).query)['state']
  end

  it 'sends the super admin to Google and connects the account it comes back with' do
    allow(Agenda::GoogleConnection).to receive(:connect!)
    allow(Agenda::GoogleConnection).to receive(:email).and_return('agenda@example.com')

    state = start_connection
    expect(response.location).to start_with(Agenda::GoogleConnection::AUTHORIZE_URL)

    get callback, params: { code: 'code-1', state: state }

    expect(Agenda::GoogleConnection).to have_received(:connect!).with(code: 'code-1', redirect_uri: end_with(callback))
    expect(flash[:success]).to include('agenda@example.com')
  end

  it 'asks for the OAuth app credentials before sending the super admin to Google' do
    allow(Agenda::GoogleConnection).to receive(:configured?).and_return(false)

    post '/super_admin/integrations/agenda_google/connect'

    expect(response).to redirect_to('/super_admin/app_config?config=google')
    expect(flash[:alert]).to include('Client ID')
  end

  it 'refuses an answer that did not start on this screen' do
    allow(Agenda::GoogleConnection).to receive(:connect!)
    start_connection

    get callback, params: { code: 'code-1', state: 'other' }

    expect(Agenda::GoogleConnection).not_to have_received(:connect!)
    expect(flash[:alert]).to be_present
  end

  it 'shows why the connection test failed' do
    allow(Agenda::GoogleConnection).to receive(:access_token).and_raise(Agenda::GoogleConnection::Error, 'expirou')

    post '/super_admin/integrations/agenda_google/test_connection'

    expect(flash[:alert]).to include('expirou')
  end

  it 'disconnects the account' do
    InstallationConfig.find_or_initialize_by(name: Agenda::GoogleConnection::REFRESH_TOKEN).update!(value: 'refresh-1')

    delete '/super_admin/integrations/agenda_google/disconnect'

    expect(Agenda::GoogleConnection).not_to be_connected
    expect(response).to redirect_to(super_admin_app_config_path(config: 'google'))
  end

  it 'renders the Google settings page with the connection panel' do
    get '/super_admin/app_config', params: { config: 'google' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Conta Google da Agenda', 'Conectar conta Google', callback)
  end

  it 'is only for super admins' do
    sign_out(:super_admin)

    post '/super_admin/integrations/agenda_google/connect'

    expect(response).to redirect_to('/super_admin/sign_in')
  end
end
