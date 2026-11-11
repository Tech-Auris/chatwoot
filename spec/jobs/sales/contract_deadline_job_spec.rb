require 'rails_helper'

RSpec.describe Sales::ContractDeadlineJob do
  let(:quote) { create(:sales_quote, billing_cycle: :annual, reserved_until: 10.days.from_now) }
  let(:client) { instance_double(Integrations::Autentique::Client, update_deadline: {}) }

  before { allow(Integrations::Autentique::Client).to receive(:new).and_return(client) }

  it 'moves the signing deadline to the new reservation date and reopens an expired contract' do
    contract = create(:sales_contract, sales_quote: quote, status: :expired, deadline_at: 1.day.ago, autentique_document_id: 'doc-9')

    described_class.perform_now(contract.id)

    expect(client).to have_received(:update_deadline).with('doc-9', quote.reserved_until)
    expect(contract.reload).to have_attributes(status: 'awaiting_signature', deadline_at: quote.reserved_until)
  end

  # Real case: the reservation lapsed, the customer generated the contract at
  # full price, the seller renewed and the contract kept the old price.
  context 'when the contract was generated while the reservation had lapsed' do
    let(:quote) do
      create(:sales_quote, billing_cycle: :annual, reserved_until: 10.days.from_now, meeting_discount: true,
                           subtotal_amount: 1_000_000, meeting_discount_amount: 100_000, discount_amount: 100_000, total_amount: 900_000)
    end
    let(:data) do
      { 'person_type' => 'pj', 'razao_social' => 'Clínica Cinco Ltda', 'cnpj' => '11.222.333/0001-81', 'nome' => 'Maria Souza',
        'cpf' => '529.982.247-25', 'email' => 'maria@clinica.com.br', 'whatsapp' => '61981402211', 'cep' => '70000000',
        'logradouro' => 'Rua A', 'numero' => '1', 'complemento' => nil, 'bairro' => 'Centro', 'cidade' => 'Brasília', 'uf' => 'DF',
        'endereco' => 'Rua A, 1, Centro, Brasília/DF, CEP 70000-000' }
    end
    let(:document) { { 'id' => 'doc-new', 'signatures' => [{ 'email' => 'maria@clinica.com.br', 'link' => { 'short_link' => 'https://assina.ae/n' } }] } }

    before do
      allow(Sales::ContractPdfService).to receive(:new).and_return(instance_double(Sales::ContractPdfService, to_pdf: '%PDF'))
      allow(Sales::ContractTemplateRenderer).to receive(:new).and_call_original
      allow(Sales::ContractSettings).to receive(:auto_sign?).and_return(false)
      allow(client).to receive_messages(create_document: document, delete_document: true)
    end

    it 'generates the contract again with the discount the renewal brought back' do
      contract = create(:sales_contract, sales_quote: quote, status: :awaiting_signature, deadline_at: nil,
                                         autentique_document_id: 'doc-old', data: data)

      described_class.perform_now(contract.id)

      expect(client).not_to have_received(:update_deadline)
      expect(client).to have_received(:delete_document).with('doc-old')
      expect(contract.reload.status).to eq('cancelled')
      expect(quote.current_contract).to have_attributes(autentique_document_id: 'doc-new', status: 'awaiting_signature',
                                                        deadline_at: quote.reserved_until, data: data)
      expect(Sales::ContractTemplateRenderer).to have_received(:new)
        .with(hash_including(variables: hash_including(valor_total: '9.000,00')))
    end
  end
end
