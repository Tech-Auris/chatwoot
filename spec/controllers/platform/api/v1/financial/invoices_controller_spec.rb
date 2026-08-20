require 'rails_helper'

RSpec.describe 'Platform Financial Invoices API', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:usage) { [{ account_id: account.id, text: 1480, media: 129, audio: 3 }] }
  let(:prices) { { text: 'price_text', media: 'price_media', audio: 'price_audio' } }
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let!(:account) { create(:account, name: 'Cardionorte', stripe_customer_id: 'cus_1') }
  let(:invoice) { Struct.new(:id, :number, :hosted_invoice_url).new('in_1', 'A-001', 'https://invoice.stripe.com/x') }

  def stripe_price(id, unit_amount)
    Struct.new(:id, :unit_amount, :currency, :nickname).new(id, unit_amount, 'brl', id)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_prices).and_return(
      Struct.new(:data).new([stripe_price('price_text', 6), stripe_price('price_media', 10), stripe_price('price_audio', 49)])
    )
  end

  describe 'POST /platform/api/v1/financial/invoices/preview' do
    it 'rejects a request without a platform token' do
      post '/platform/api/v1/financial/invoices/preview', params: { usage: usage, prices: prices }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # An automation has to be able to check the total before committing to it,
    # the same way the screen does.
    it 'prices the run without issuing anything' do
      expect(client).not_to receive(:create_invoice)

      post '/platform/api/v1/financial/invoices/preview',
           params: { usage: usage, prices: prices },
           headers: { api_access_token: platform_app.access_token.token }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['total_amount']).to eq(10_317)
    end
  end

  describe 'POST /platform/api/v1/financial/invoices' do
    it 'issues the invoices of the batch' do
      expect(client).to receive(:create_invoice).with(
        hash_including(customer_id: 'cus_1', description: 'Cobrança Tokens - Julho/2026')
      ).and_return(invoice)

      post '/platform/api/v1/financial/invoices',
           params: { usage: usage, prices: prices, description: 'Cobrança Tokens - Julho/2026', period: '2026-07' },
           headers: { api_access_token: platform_app.access_token.token }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('issued_count' => 1)
    end

    # The monthly automation should not carry a copy of the price ids that
    # silently goes stale — it falls back to what the finance team last chose.
    it 'falls back to the prices saved on the screen when none are sent' do
      { 'STRIPE_TOKEN_PRICE_TEXT' => 'price_text', 'STRIPE_TOKEN_PRICE_MEDIA' => 'price_media',
        'STRIPE_TOKEN_PRICE_AUDIO' => 'price_audio' }.each do |key, value|
        InstallationConfig.create!(name: key, value: value)
      end
      GlobalConfig.clear_cache
      allow(client).to receive(:create_invoice).and_return(invoice)

      post '/platform/api/v1/financial/invoices',
           params: { usage: usage },
           headers: { api_access_token: platform_app.access_token.token }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['issued_count']).to eq(1)
    end

    it 'reports a row it could not bill instead of failing the whole call' do
      unlinked = create(:account, name: 'Sem Vínculo')

      post '/platform/api/v1/financial/invoices',
           params: { usage: [{ account_id: unlinked.id, text: 10, media: 0, audio: 0 }], prices: prices },
           headers: { api_access_token: platform_app.access_token.token }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['results'].first).to include('status' => 'skipped')
      expect(response.parsed_body['issued_count']).to eq(0)
    end
  end
end
