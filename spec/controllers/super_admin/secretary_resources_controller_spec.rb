require 'rails_helper'

RSpec.describe 'Super Admin secretary resources', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:secretary_resource) { create(:secretary_resource, account: account, key: 'tabela_precos') }

  before { sign_in(super_admin, scope: :super_admin) }

  it "lists an account's resources" do
    create(:secretary_resource, key: 'de_outra_conta')

    get '/super_admin/secretary_resources', params: { search: "account:#{account.id}" }

    expect(response.body).to include('tabela_precos')
    expect(response.body).not_to include('de_outra_conta')
  end

  it 'renders the form with the resource types' do
    get '/super_admin/secretary_resources/new'

    expect(response.body).to include('1 · image')
  end

  it 'creates a resource' do
    post '/super_admin/secretary_resources', params: {
      secretary_resource: { account_id: account.id, key: 'endereco', idioma: '', secretary_resource_type_id: 1,
                            resource_url: 'https://example.com/mapa.png', caption: 'Nosso endereço' }
    }

    expect(account.secretary_resources.find_by(key: 'endereco')).to have_attributes(idioma: nil, caption: 'Nosso endereço')
  end

  it 'edits a resource' do
    patch "/super_admin/secretary_resources/#{secretary_resource.id}", params: { secretary_resource: { caption: 'Nova legenda' } }

    expect(secretary_resource.reload.caption).to eq('Nova legenda')
  end

  it 'removes a resource' do
    delete "/super_admin/secretary_resources/#{secretary_resource.id}"

    expect(SecretaryResource.exists?(secretary_resource.id)).to be(false)
  end
end
