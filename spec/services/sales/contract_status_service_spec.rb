require 'rails_helper'

RSpec.describe Sales::ContractStatusService do
  let(:contract) { create(:sales_contract, deadline_at: 2.days.from_now) }
  let(:client) { instance_double(Integrations::Autentique::Client) }

  def signatures(customer)
    { 'id' => contract.autentique_document_id,
      'signatures' => [{ 'email' => 'daniel@agenteauris.com.br', 'signed' => { 'created_at' => '2026-10-03T10:00:00Z' } },
                       customer.merge('email' => 'MARIA@clinica.com.br')] }
  end

  def refresh
    described_class.new(contract, client: client).refresh!
  end

  it "marks the contract signed when the customer's signature is in" do
    allow(client).to receive(:document).and_return(signatures('signed' => { 'created_at' => '2026-10-03T13:42:00Z' }))

    refresh

    expect(contract.reload).to have_attributes(status: 'signed', signed_at: Time.zone.parse('2026-10-03T13:42:00Z'))
    expect(contract.sales_quote.events.pluck(:event)).to include('contract_signed')
  end

  it 'marks the contract rejected when the customer refused it' do
    allow(client).to receive(:document).and_return(signatures('rejected' => { 'created_at' => '2026-10-03T13:42:00Z' }))

    expect(refresh.status).to eq('rejected')
  end

  it 'marks it expired once the deadline passed without the signature' do
    contract.update!(deadline_at: 1.minute.ago)
    allow(client).to receive(:document).and_return(signatures({}))

    expect(refresh.status).to eq('expired')
  end

  it 'leaves the contract as it was when Autentique is down' do
    allow(client).to receive(:document).and_raise(Integrations::Autentique::Client::ProviderUnavailable, '502')

    expect(refresh.status).to eq('awaiting_signature')
  end
end
