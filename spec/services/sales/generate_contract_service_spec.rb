require 'rails_helper'

RSpec.describe Sales::GenerateContractService do
  let(:quote) do
    create(:sales_quote, billing_cycle: :annual, reserved_until: 5.days.from_now, prospect_name: 'Maria Souza',
                         prospect_email: 'maria@clinica.com.br', prospect_document: '52998224725', company_name: 'Clínica Cinco',
                         total_amount: 2_219_040, subtotal_amount: 2_219_040)
  end
  let(:client) { instance_double(Integrations::Autentique::Client) }
  let(:form) do
    Sales::ContractForm.new(person_type: 'pj', razao_social: 'Clínica Cinco Ltda', cnpj: '11.222.333/0001-81', nome: 'Maria Souza',
                            cpf: '529.982.247-25', email: 'maria@clinica.com.br', whatsapp: '61981402211', cep: '70000000',
                            logradouro: 'Rua A', numero: '1', bairro: 'Centro', cidade: 'Brasília', uf: 'DF', payment_method: 'card')
  end
  let(:document) do
    { 'id' => 'doc-1', 'signatures' => [{ 'email' => 'daniel@agenteauris.com.br', 'link' => { 'short_link' => 'https://assina.ae/auris' } },
                                        { 'email' => 'maria@clinica.com.br', 'link' => { 'short_link' => 'https://assina.ae/maria' } }] }
  end

  before do
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Auris', unit_amount: 2_219_040)
    pdf = instance_double(Sales::ContractPdfService, to_pdf: '%PDF')
    allow(Sales::ContractPdfService).to receive(:new).and_return(pdf)
    allow(client).to receive(:me).and_return('email' => 'daniel@agenteauris.com.br')
    allow(client).to receive(:create_document).and_return(document)
    allow(client).to receive(:sign_document).and_return(true)
    allow(client).to receive(:delete_document).and_return(true)
  end

  def perform
    described_class.new(quote: quote, form: form, client: client).perform
  end

  it 'creates the document with Auris signing first, signs for Auris and waits for the customer' do
    contract = perform

    expect(client).to have_received(:create_document).with(hash_including(
                                                             signers: [{ email: 'daniel@agenteauris.com.br', action: 'SIGN' },
                                                                       { email: 'maria@clinica.com.br', action: 'SIGN' }],
                                                             deadline_at: quote.reserved_until
                                                           ))
    expect(client).to have_received(:sign_document).with('doc-1')
    expect(contract).to have_attributes(status: 'awaiting_signature', autentique_document_id: 'doc-1',
                                        signing_url: 'https://assina.ae/maria', payment_method: 'card', installments: 12)
    expect(contract.auris_signed_at).to be_present
    expect(contract.template_version).to eq(SalesContractTemplate.current.version)
  end

  it 'comments on the ClickUp task that the contract went out' do
    expect { perform }.to have_enqueued_job(Sales::ContractClickupCommentJob).with(kind_of(Integer), 'generated')
  end

  it 'asks Autentique for the signing link when the e-mail signer has none' do
    document['signatures'][1] = { 'public_id' => 'sig-maria', 'email' => 'maria@clinica.com.br', 'link' => nil }
    allow(client).to receive(:signature_link).with('sig-maria').and_return('https://assina.ae/novo')

    expect(perform.signing_url).to eq('https://assina.ae/novo')
  end

  it 'does not sign for Auris when the automatic signature is off' do
    Sales::ContractSettings.update!(enabled: true, auto_sign: false)

    perform

    expect(client).not_to have_received(:sign_document)
    expect(client).to have_received(:create_document).with(hash_including(signers: [{ email: 'maria@clinica.com.br', action: 'SIGN' }]))
  end

  it 'keeps the contract as failed, never sent, when Auris cannot sign' do
    allow(client).to receive(:sign_document).and_raise(Integrations::Autentique::Client::Error, 'signature_not_found')

    expect { perform }.to raise_error(described_class::Error, /Erro na assinatura da Auris/)
    expect(quote.contracts.last).to have_attributes(status: 'failed', error_message: /signature_not_found/)
  end

  it 'replaces the previous contract, taking its document down on Autentique' do
    previous = create(:sales_contract, sales_quote: quote, autentique_document_id: 'doc-old')

    perform

    expect(client).to have_received(:delete_document).with('doc-old')
    expect(previous.reload).to have_attributes(status: 'cancelled')
    expect(quote.current_contract.autentique_document_id).to eq('doc-1')
  end

  it 'never replaces a signed contract' do
    create(:sales_contract, sales_quote: quote, status: :signed)

    expect { perform }.to raise_error(described_class::Error, 'O contrato já foi assinado')
  end

  it 'refuses boleto while the seller has not enabled it' do
    form.payment_method = 'boleto'

    expect { perform }.to raise_error(described_class::Error, /não disponível/)
  end
end
