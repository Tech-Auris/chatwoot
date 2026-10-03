require 'rails_helper'

RSpec.describe 'Super Admin commercial contract', type: :request do
  let(:super_admin) { create(:super_admin, name: 'Fabio') }
  let(:base) { '/super_admin/commercial/contract' }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'renders the page' do
    get base

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('CommercialContract')
  end

  it 'returns both switches on by default and the first template version' do
    get "#{base}/data", as: :json

    expect(response.parsed_body).to include('enabled' => true, 'auto_sign' => true)
    expect(response.parsed_body.dig('template', 'version')).to eq(1)
  end

  it 'turns the contract step and the automatic signature off' do
    patch "#{base}/settings", params: { enabled: false, auto_sign: false }, as: :json

    expect(Sales::ContractSettings.enabled?).to be(false)
    expect(Sales::ContractSettings.auto_sign?).to be(false)
  end

  it 'saves the editor content as a new version, by who saved it' do
    SalesContractTemplate.current

    post "#{base}/templates", params: { content: '<p>{{cnpj}}</p>' }, as: :json

    expect(response.parsed_body['template']).to include('version' => 2, 'content' => '<p>{{cnpj}}</p>', 'created_by_name' => 'Fabio')
  end

  it 'returns a PDF preview of the editor content filled with sample data' do
    rendered = nil
    pdf = instance_double(Sales::ContractPdfService, to_pdf: '%PDF-preview')
    allow(Sales::ContractPdfService).to receive(:new) { |html| (rendered = html) && pdf }

    post "#{base}/preview", params: { content: '{{#se_pf}}{{nome_completo}}{{/se_pf}}', person_type: 'pf' }, as: :json

    expect(rendered).to eq('Ana Maria Souza')
    expect(response.media_type).to eq('application/pdf')
    expect(response.body).to eq('%PDF-preview')
  end

  it "says who signs for Auris from the Autentique token's account" do
    InstallationConfig.find_or_initialize_by(name: 'AUTENTIQUE_API_TOKEN').update!(value: 'token-123')
    GlobalConfig.clear_cache
    stub_request(:post, 'https://api.autentique.com.br/v2/graphql')
      .to_return(status: 200, body: { data: { me: { id: '1', name: 'Daniel', email: 'daniel@agenteauris.com.br' } } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    get "#{base}/signer", as: :json

    expect(response.parsed_body).to eq('name' => 'Daniel', 'email' => 'daniel@agenteauris.com.br')
  end
end
