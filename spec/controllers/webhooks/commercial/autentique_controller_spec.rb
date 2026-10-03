require 'rails_helper'

RSpec.describe 'Autentique webhook', type: :request do
  let(:secret) { 'webhook-secret' }
  let!(:contract) { create(:sales_contract, autentique_document_id: 'doc-42') }
  let(:body) { { event: { type: 'signature.accepted', data: { object: { public_id: 'sig-1', document: { id: 'doc-42' } } } } }.to_json }

  before do
    InstallationConfig.find_or_initialize_by(name: 'AUTENTIQUE_WEBHOOK_SECRET').update!(value: secret)
    GlobalConfig.clear_cache
  end

  def deliver(signature)
    post '/webhooks/commercial/autentique', params: body, headers: { 'Content-Type' => 'application/json', 'x-autentique-signature' => signature }
  end

  it 'refreshes the contract the event is about when the signature matches' do
    service = instance_double(Sales::ContractStatusService, refresh!: contract)
    allow(Sales::ContractStatusService).to receive(:new).with(contract).and_return(service)

    deliver(OpenSSL::HMAC.hexdigest('SHA256', secret, body))

    expect(response).to have_http_status(:ok)
    expect(service).to have_received(:refresh!)
  end

  it 'refuses a payload Autentique did not sign' do
    deliver('forged')

    expect(response).to have_http_status(:unauthorized)
  end
end
