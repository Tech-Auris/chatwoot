require 'rails_helper'

RSpec.describe Integrations::Asaas::Client do
  subject(:client) { described_class.new(api_key: '$aact_prod_key') }

  let(:link) { { 'id' => 'pay_link_1', 'url' => 'https://www.asaas.com/c/pay_link_1' } }

  describe '#create_payment_link' do
    # The shape AsaaS documents for an instalment link: credit card only, with
    # the cap the customer may split into.
    it 'asks for a card link split into instalments' do
      request = stub_request(:post, 'https://api.asaas.com/v3/paymentLinks')
                .with(body: hash_including('billingType' => 'CREDIT_CARD', 'chargeType' => 'INSTALLMENT',
                                           'maxInstallmentCount' => 12, 'notificationEnabled' => false))
                .to_return(status: 200, body: link.to_json, headers: { 'Content-Type' => 'application/json' })

      client.create_payment_link(name: 'AurisChat — Clínica Cinco', value_cents: 1_286_760, max_installment_count: 12)

      expect(request).to have_been_requested
    end

    # AsaaS counts in reais where Stripe counts in cents.
    it 'sends the amount in reais' do
      request = stub_request(:post, 'https://api.asaas.com/v3/paymentLinks')
                .with(body: hash_including('value' => 12_867.60))
                .to_return(status: 200, body: link.to_json, headers: { 'Content-Type' => 'application/json' })

      client.create_payment_link(name: 'Proposta', value_cents: 1_286_760)

      expect(request).to have_been_requested
    end

    it 'answers with the link the customer opens' do
      stub_request(:post, 'https://api.asaas.com/v3/paymentLinks')
        .to_return(status: 200, body: link.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.create_payment_link(name: 'Proposta', value_cents: 50_000)['url'])
        .to eq('https://www.asaas.com/c/pay_link_1')
    end

    it 'carries the key on the header AsaaS reads' do
      request = stub_request(:post, 'https://api.asaas.com/v3/paymentLinks')
                .with(headers: { 'access_token' => '$aact_prod_key' })
                .to_return(status: 200, body: link.to_json, headers: { 'Content-Type' => 'application/json' })

      client.create_payment_link(name: 'Proposta', value_cents: 50_000)

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
      stub_request(:post, 'https://api.asaas.com/v3/paymentLinks').to_return(status: 401, body: '{}')

      expect { client.create_payment_link(name: 'Proposta', value_cents: 50_000) }
        .to raise_error(described_class::Unauthorized, /credencial/)
    end

    # AsaaS explains a refusal in `errors`, and that explanation is what the
    # page can show the customer.
    it 'repeats what AsaaS complained about' do
      stub_request(:post, 'https://api.asaas.com/v3/paymentLinks')
        .to_return(status: 400, body: { errors: [{ description: 'O valor mínimo é R$ 5,00' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.create_payment_link(name: 'Proposta', value_cents: 100) }
        .to raise_error(described_class::ProviderUnavailable, /valor mínimo/)
    end

    it 'says the provider is unreachable when the call cannot be made' do
      stub_request(:post, 'https://api.asaas.com/v3/paymentLinks').to_raise(SocketError.new('getaddrinfo'))

      expect { client.create_payment_link(name: 'Proposta', value_cents: 50_000) }
        .to raise_error(described_class::ProviderUnavailable)
    end
  end

  describe '#configured?' do
    it 'is false without a key' do
      expect(described_class.new(api_key: '')).not_to be_configured
    end
  end
end
