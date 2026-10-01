require 'rails_helper'

RSpec.describe 'Super Admin secretary versions', type: :request do
  let(:super_admin) { create(:super_admin) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'lists the versions' do
    create(:secretary_version, name: 'v3.3')

    get '/super_admin/secretary_versions'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('v3.3')
  end

  it 'registers a new version in testing' do
    post '/super_admin/secretary_versions', params: {
      secretary_version: { name: 'v3.4', webhook_url: 'https://n8n.example.com/webhook/v3_4', status: 'testing' }
    }

    expect(SecretaryVersion.find_by(name: 'v3.4')).to be_testing
  end
end
