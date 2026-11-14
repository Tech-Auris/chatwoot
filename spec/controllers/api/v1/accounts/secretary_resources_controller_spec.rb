require 'rails_helper'

RSpec.describe 'Secretary resources API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:doc_type) { SecretaryResourceType.find_or_create_by!(id: 6) { |type| type.description = 'doc' } }

  before { create(:secretary_resource, account: account, key: 'tabela', caption: 'Padrão', secretary_resource_type: doc_type) }

  def lookup(params)
    get "/api/v1/accounts/#{account.id}/secretary_resources/lookup", params: params, headers: agent.create_new_auth_token, as: :json
  end

  it 'returns unauthorized without a token' do
    get "/api/v1/accounts/#{account.id}/secretary_resources/lookup", params: { key: 'tabela' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the resource in the asked language, in the Supabase row shape' do
    create(:secretary_resource, account: account, key: 'tabela', idioma: 'en', caption: 'English')

    lookup(key: 'tabela', idioma: 'en')

    expect(response.parsed_body).to include('cliente_id' => account.id, 'key' => 'tabela', 'idioma' => 'en', 'caption' => 'English')
  end

  it 'falls back to the resource without a language' do
    lookup(key: 'tabela', idioma: 'es')

    expect(response.parsed_body).to include('caption' => 'Padrão', 'idioma' => nil, 'resource_type' => 6)
  end

  it 'returns not found when no resource matches' do
    lookup(key: "tabela' or '1'='1")

    expect(response).to have_http_status(:not_found)
  end

  it "doesn't return another account's resource" do
    create(:secretary_resource, key: 'outra')

    lookup(key: 'outra')

    expect(response).to have_http_status(:not_found)
  end
end
