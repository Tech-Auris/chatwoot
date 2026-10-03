require 'rails_helper'

RSpec.describe 'Autentique webhook', type: :request do
  let(:secret) { 'webhook-code-123' }
  let!(:contract) { create(:sales_contract, autentique_document_id: 'doc-42') }
  let(:body) { { event: { type: 'signature.accepted', data: { object: { public_id: 'sig-1', document: { id: 'doc-42' } } } } }.to_json }

  before do
    InstallationConfig.find_or_initialize_by(name: 'AUTENTIQUE_WEBHOOK_SECRET').update!(value: secret)
    GlobalConfig.clear_cache
  end

  def deliver(code)
    post "/webhooks/commercial/autentique/#{code}", params: body, headers: { 'Content-Type' => 'application/json' }
  end

  it 'refreshes the contract the event is about when the URL carries the webhook code' do
    service = instance_double(Sales::ContractStatusService, refresh!: contract)
    allow(Sales::ContractStatusService).to receive(:new).with(contract).and_return(service)

    deliver(secret)

    expect(response).to have_http_status(:ok)
    expect(service).to have_received(:refresh!)
  end

  it 'refuses a call without the right code' do
    deliver('wrong')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses everything while no code is configured' do
    InstallationConfig.find_by(name: 'AUTENTIQUE_WEBHOOK_SECRET').update!(value: '')
    GlobalConfig.clear_cache

    deliver('')

    expect(response.status).to be_in([401, 404])
  end
end
