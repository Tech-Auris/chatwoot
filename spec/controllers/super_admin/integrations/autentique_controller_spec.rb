require 'rails_helper'

RSpec.describe 'Super Admin Autentique integration', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    InstallationConfig.find_or_initialize_by(name: 'AUTENTIQUE_API_TOKEN').update!(value: 'token-123')
    GlobalConfig.clear_cache
    sign_in(super_admin, scope: :super_admin)
  end

  it 'says whose account will sign the contracts' do
    stub_request(:post, 'https://api.autentique.com.br/v2/graphql')
      .to_return(status: 200, body: { data: { me: { id: '1', name: 'Daniel', email: 'daniel@agenteauris.com.br' } } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    post '/super_admin/integrations/autentique/test_connection'

    expect(response).to redirect_to(super_admin_app_config_path(config: 'autentique'))
    expect(flash[:success]).to include('Daniel (daniel@agenteauris.com.br)')
  end

  it 'flags an invalid token' do
    stub_request(:post, 'https://api.autentique.com.br/v2/graphql').to_return(status: 401, body: '')

    post '/super_admin/integrations/autentique/test_connection'

    expect(flash[:alert]).to include('Token do Autentique inválido')
  end

  it 'renders the settings page with the connection panel' do
    get '/super_admin/app_config', params: { config: 'autentique' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Conexão com o Autentique', 'Testar conexão')
  end
end
