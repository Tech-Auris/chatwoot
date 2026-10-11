require 'rails_helper'

RSpec.describe Sales::AccountCreatedWebhookJob do
  let(:webhook_url) { 'https://n8n.example.com/webhook/cadastro-final' }
  let(:quote) do
    create(:sales_quote, prospect_name: 'Felicia Macedo', company_name: 'Clínica Cinco', company_document: '11222333000181',
                         prospect_email: 'contato@clinicacinco.com.br', billing_cycle: :annual, payment_method: :pix,
                         subtotal_amount: 1_076_400, total_amount: 1_076_400, status: :paid)
  end
  let(:account) { Sales::ConvertQuoteService.new(quote: quote).perform.account }

  before do
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Pro', unit_amount: 89_700, quantity: 12)
    account
    InstallationConfig.where(name: described_class::URL_CONFIG).first_or_create!(value: webhook_url)
    InstallationConfig.where(name: described_class::SECRET_CONFIG).first_or_create!(value: 'shh')
  end

  it 'posts the account, customer, company and plan, signed with the secret' do
    stub = stub_request(:post, webhook_url).with do |request|
      body = JSON.parse(request.body)
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'shh', request.body)}"
      request.headers['X-Auris-Signature'] == signature &&
        body['event'] == 'account.created' &&
        body['account']['id'] == account.id && body['account']['name'] == 'Clínica Cinco' &&
        body['customer']['email'] == 'contato@clinicacinco.com.br' &&
        body['company']['document'] == '11222333000181' &&
        body['plan']['billing_cycle'] == 'annual' && body['plan']['items'].first['quantity'] == 12 &&
        body['sale']['quote_id'] == quote.id
    end.to_return(status: 200)

    described_class.perform_now(quote.id)

    expect(stub).to have_been_requested
    expect(quote.events.where(event: 'account_webhook_sent')).to exist
  end

  it 'does nothing while no webhook is configured' do
    InstallationConfig.find_by(name: described_class::URL_CONFIG).update!(value: '')

    described_class.perform_now(quote.id)

    expect(WebMock).not_to have_requested(:post, webhook_url)
  end

  it 'retries when the flow answers with an error' do
    stub_request(:post, webhook_url).to_return(status: 502, body: 'bad gateway')

    expect { described_class.perform_now(quote.id) }.to have_enqueued_job(described_class).with(quote.id)
    expect(quote.events.where(event: 'account_webhook_sent')).not_to exist
  end
end
