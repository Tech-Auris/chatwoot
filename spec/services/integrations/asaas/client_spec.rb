require 'rails_helper'

RSpec.describe Integrations::Asaas::Client do
  subject(:client) { described_class.new(api_key: '$aact_prod_key') }

  let(:customer) { { 'id' => 'cus_pl6ye1o01', 'name' => 'Clínica Cinco', 'cpfCnpj' => '52998224725' } }
  let(:installment) { { 'id' => 'inst_kf3ndj7q1', 'installmentCount' => 6, 'totalValue' => 5382.00, 'billingType' => 'BOLETO' } }

  describe '#find_customer' do
    it 'looks the customer up by document, digits only' do
      request = stub_request(:get, 'https://api.asaas.com/v3/customers')
                .with(query: hash_including('cpfCnpj' => '52998224725'))
                .to_return(status: 200, body: { data: [customer] }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      expect(client.find_customer(cpf_cnpj: '529.982.247-25')).to eq(customer)
      expect(request).to have_been_requested
    end

    # A blank document is not a lookup we want to make — AsaaS would answer
    # every customer they have on file.
    it 'answers nil for a blank document without hitting AsaaS' do
      expect(client.find_customer(cpf_cnpj: '')).to be_nil
    end

    it 'answers nil when the customer is not on file' do
      stub_request(:get, 'https://api.asaas.com/v3/customers')
        .with(query: hash_including('cpfCnpj' => '52998224725'))
        .to_return(status: 200, body: { data: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.find_customer(cpf_cnpj: '52998224725')).to be_nil
    end
  end

  describe '#create_customer' do
    it 'sends the prospect through with notifications off' do
      request = stub_request(:post, 'https://api.asaas.com/v3/customers')
                .with(body: hash_including('name' => 'Clínica Cinco', 'email' => 'contato@clinica.com',
                                           'cpfCnpj' => '52998224725', 'notificationDisabled' => true))
                .to_return(status: 200, body: customer.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_customer(name: 'Clínica Cinco', email: 'contato@clinica.com', cpf_cnpj: '529.982.247-25')

      expect(request).to have_been_requested
    end

    it 'answers with the customer AsaaS created' do
      stub_request(:post, 'https://api.asaas.com/v3/customers')
        .to_return(status: 200, body: customer.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.create_customer(name: 'Clínica Cinco', email: 'contato@clinica.com', cpf_cnpj: '52998224725')['id'])
        .to eq('cus_pl6ye1o01')
    end
  end

  describe '#create_installment' do
    # The number of parcels is locked at N: AsaaS creates N payments under one
    # instalment id, one due date per month.
    it 'asks for an instalment of the plan against the customer' do
      request = stub_request(:post, 'https://api.asaas.com/v3/installments')
                .with(body: hash_including('customer' => 'cus_pl6ye1o01', 'billingType' => 'BOLETO',
                                           'installmentCount' => 6, 'totalValue' => 5382.00))
                .to_return(status: 200, body: installment.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_installment(customer_id: 'cus_pl6ye1o01', billing_type: 'BOLETO',
                                total_value_cents: 538_200, installment_count: 6,
                                due_date: Date.new(2026, 9, 20))

      expect(request).to have_been_requested
    end

    # AsaaS counts in reais where Stripe counts in cents.
    it 'sends the total in reais' do
      request = stub_request(:post, 'https://api.asaas.com/v3/installments')
                .with(body: hash_including('totalValue' => 12_867.60))
                .to_return(status: 200, body: installment.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_installment(customer_id: 'cus_x', billing_type: 'CREDIT_CARD',
                                total_value_cents: 1_286_760, installment_count: 12,
                                due_date: Date.new(2026, 9, 20))

      expect(request).to have_been_requested
    end

    it 'sends the first due date as an ISO calendar date' do
      request = stub_request(:post, 'https://api.asaas.com/v3/installments')
                .with(body: hash_including('dueDate' => '2026-09-20'))
                .to_return(status: 200, body: installment.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_installment(customer_id: 'cus_x', billing_type: 'BOLETO',
                                total_value_cents: 100_000, installment_count: 6,
                                due_date: Date.new(2026, 9, 20))

      expect(request).to have_been_requested
    end
  end

  describe '#list_installment_payments' do
    let(:payments) do
      [
        { 'id' => 'pay_1', 'dueDate' => '2026-09-20', 'invoiceUrl' => 'https://www.asaas.com/i/1' },
        { 'id' => 'pay_2', 'dueDate' => '2026-10-20', 'invoiceUrl' => 'https://www.asaas.com/i/2' }
      ]
    end

    it 'answers with the payments AsaaS opened under the instalment' do
      stub_request(:get, 'https://api.asaas.com/v3/installments/inst_kf3ndj7q1/payments')
        .to_return(status: 200, body: { data: payments }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.list_installment_payments('inst_kf3ndj7q1')).to eq(payments)
    end
  end

  describe '#delete_installment' do
    it 'asks AsaaS to cancel the whole book' do
      request = stub_request(:delete, 'https://api.asaas.com/v3/installments/inst_kf3ndj7q1')
                .to_return(status: 200, body: { deleted: true }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.delete_installment('inst_kf3ndj7q1')

      expect(request).to have_been_requested
    end
  end

  # The same account has a sandbox key and a production key, each answering on
  # its own host — the key itself says which.
  describe 'which environment it talks to' do
    it 'takes a homologation key to the sandbox' do
      sandbox = described_class.new(api_key: '$aact_hmlg_key')

      expect(sandbox.base_url).to eq(described_class::SANDBOX_URL)
      expect(sandbox).to be_sandbox
    end

    it 'takes a production key to production' do
      expect(client.base_url).to eq(described_class::PRODUCTION_URL)
      expect(client).not_to be_sandbox
    end
  end

  describe 'when the call fails' do
    it 'says the credential was refused' do
      stub_request(:post, 'https://api.asaas.com/v3/customers').to_return(status: 401, body: '{}')

      expect { client.create_customer(name: 'X', email: 'x@x.com', cpf_cnpj: '52998224725') }
        .to raise_error(described_class::Unauthorized, /credencial/)
    end

    # AsaaS explains a refusal in `errors`, and that explanation is what the
    # page can show the customer.
    it 'repeats what AsaaS complained about' do
      stub_request(:post, 'https://api.asaas.com/v3/installments')
        .to_return(status: 400, body: { errors: [{ description: 'O valor mínimo é R$ 5,00' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect do
        client.create_installment(customer_id: 'cus_x', billing_type: 'BOLETO',
                                  total_value_cents: 100, installment_count: 2,
                                  due_date: Date.new(2026, 9, 20))
      end.to raise_error(described_class::ProviderUnavailable, /valor mínimo/)
    end

    it 'says the provider is unreachable when the call cannot be made' do
      stub_request(:post, 'https://api.asaas.com/v3/customers').to_raise(SocketError.new('getaddrinfo'))

      expect { client.create_customer(name: 'X', email: 'x@x.com', cpf_cnpj: '52998224725') }
        .to raise_error(described_class::ProviderUnavailable)
    end
  end

  describe '#configured?' do
    it 'is false without a key' do
      expect(described_class.new(api_key: '')).not_to be_configured
    end
  end
end
