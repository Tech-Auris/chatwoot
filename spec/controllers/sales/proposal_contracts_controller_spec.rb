require 'rails_helper'

RSpec.describe 'Public sales proposal – contract step', type: :request do
  let(:quote) do
    create(:sales_quote, billing_cycle: :annual, prospect_phone: '+55 61 98140-2211', reserved_until: 5.days.from_now,
                         prospect_name: 'Maria Souza', prospect_email: 'maria@clinica.com.br', prospect_document: '52998224725',
                         company_name: 'Clínica Cinco', company_document: '11222333000181', billing_name: 'Clínica Cinco Ltda',
                         total_amount: 2_219_040, subtotal_amount: 2_219_040)
  end
  let(:token) { quote.public_token }
  let(:contract_params) do
    { person_type: 'pj', razao_social: 'Clínica Cinco Ltda', cnpj: '11.222.333/0001-81', nome: 'Maria Souza', cpf: '529.982.247-25',
      email: 'maria@clinica.com.br', whatsapp: '61981402211', cep: '70000-000', logradouro: 'Rua A', numero: '1',
      bairro: 'Centro', cidade: 'Brasília', uf: 'DF', payment_method: 'pix' }
  end

  before do
    Redis::Alfred.with { |conn| conn.keys('sales_proposal_attempts/*').each { |key| conn.del(key) } }
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Auris', unit_amount: 2_219_040)
    stub_request(:get, Sales::TermsFetcherService::DEFAULT_URL)
      .to_return(status: 200, body: '<html><body><h1>Termos</h1><p>Conteúdo dos termos.</p></body></html>')
    post "/proposals/#{token}/unlock", params: { access_code: quote.access_code, phone_last4: '2211' }
  end

  def accept_terms
    get "/proposals/#{token}/termos"
    post "/proposals/#{token}/termos", params: { accept_terms: '1', terms_version_id: TermsVersion.last.id }
  end

  it 'takes a long plan from the proposal to the terms page, with the plan and the Contrato step' do
    get "/proposals/#{token}"
    expect(response).to redirect_to("/proposals/#{token}/termos")

    follow_redirect!
    expect(response.body).to include('Termos de uso da Plataforma Auris', 'Plano Auris', 'Assinar Termos de Uso e continuar', '. Contrato<')
  end

  it 'records the terms acceptance and opens the contract form, prefilled from the reservation' do
    accept_terms

    expect(response).to redirect_to("/proposals/#{token}/contrato")
    expect(quote.terms_signed?).to be(true)
    follow_redirect!
    expect(response.body).to include('Confirme os dados para o contrato', 'Clínica Cinco Ltda', 'Maria Souza', 'PIX à vista')
  end

  it 'keeps the payment page shut until the contract is signed' do
    accept_terms

    get "/proposals/#{token}/pagamento"

    expect(response).to redirect_to("/proposals/#{token}/contrato")
  end

  it 'shows what is wrong with the data instead of generating the contract' do
    accept_terms

    post "/proposals/#{token}/contrato", params: { contract: contract_params.merge(cpf: '111.111.111-11', cep: '') }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('CPF inválido', 'CEP é obrigatório')
  end

  it 'tells the customer the contract is being generated while the first click is still running' do
    accept_terms
    lock_key = format(Sales::GenerateContractService::GENERATION_LOCK, quote_id: quote.id)
    Redis::Alfred.set(lock_key, 1, ex: 60)

    get "/proposals/#{token}/contrato"

    expect(response.body).to include('Seu contrato está sendo gerado')
  ensure
    Redis::Alfred.delete(lock_key)
  end

  it 'generates the contract and shows it waiting for the signature' do
    accept_terms
    allow(Sales::GenerateContractService).to receive(:new) do |quote:, form:|
      instance_double(Sales::GenerateContractService, perform: create(:sales_contract, sales_quote: quote, payment_method: form.payment_method))
    end
    allow(Sales::ContractStatusService).to receive(:new) { |contract| instance_double(Sales::ContractStatusService, refresh!: contract) }

    post "/proposals/#{token}/contrato", params: { contract: contract_params }
    follow_redirect!

    expect(response.body).to include('Contrato enviado para assinatura', 'Já assinou? Verificar assinatura', 'Conferir contrato')
  end

  it 'opens the payment page once signed, with the payment method of the contract and without the terms again' do
    accept_terms
    create(:sales_contract, sales_quote: quote, status: :signed, signed_at: Time.current, payment_method: 'pix')

    get "/proposals/#{token}/pagamento"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Forma de pagamento definida no contrato', 'PIX à vista')
    expect(response.body).not_to include('Li e aceito')
  end

  it 'pays with the method in the signed contract, whatever the form sends' do
    accept_terms
    create(:sales_contract, sales_quote: quote, status: :signed, signed_at: Time.current, payment_method: 'pix')
    checkout = instance_double(Sales::CheckoutService, perform: Sales::CheckoutService::Result.new(quote: quote))
    allow(Sales::CheckoutService).to receive(:new).and_return(checkout)

    post "/proposals/#{token}/pagamento", params: { payment_method: 'card' }

    expect(Sales::CheckoutService).to have_received(:new).with(hash_including(payment_method: 'pix'))
  end

  it 'keeps the monthly plan on the single terms-and-payment page' do
    quote.update!(billing_cycle: :monthly)

    get "/proposals/#{token}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('. Contrato<')
  end
end
