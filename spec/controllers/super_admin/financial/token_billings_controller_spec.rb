require 'rails_helper'

RSpec.describe 'Super Admin token billing', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:catalog) do
    [stripe_price('price_text', 6, 'Mensagens de Texto'),
     stripe_price('price_media', 10, 'Respostas a imagens'),
     stripe_price('price_audio', 49, 'Mensagens de Áudio')]
  end
  let(:csv) do
    "accountid,accountname,texto,imagem arquivo e transcrições,audio\n#{account.id},Cardionorte,1480,129,3\n"
  end
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }
  let!(:account) { create(:account, name: 'Cardionorte', stripe_customer_id: 'cus_1') }

  def stripe_price(id, unit_amount, nickname)
    Struct.new(:id, :product, :unit_amount, :currency, :nickname, :active, :recurring)
          .new(id, 'prod_1', unit_amount, 'brl', nickname, true, nil)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_prices).and_return(Struct.new(:data).new(catalog))
    allow(client).to receive(:list_products).and_return(Struct.new(:data).new([Struct.new(:id, :name).new('prod_1', 'Tokens')]))
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/financial/token_billings' do
    it 'renders the screen' do
      get '/super_admin/financial/token_billings'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialTokenBillingsIndex')
    end
  end

  describe 'GET /super_admin/financial/token_billings/data' do
    # A product carries a one-off price and a monthly one, usually of the same
    # amount — without the product and the recurrence the two are impossible to
    # tell apart in the picker.
    it 'says which product each price belongs to and whether it recurs' do
      recurring = Struct.new(:id, :product, :unit_amount, :currency, :nickname, :active, :recurring)
                        .new('price_text_mensal', 'prod_1', 6, 'brl', 'Mensagens de Texto', true, Struct.new(:interval).new('month'))
      allow(client).to receive(:list_prices).and_return(Struct.new(:data).new(catalog + [recurring]))

      get '/super_admin/financial/token_billings/data'

      by_id = response.parsed_body['prices'].index_by { |price| price['id'] }
      expect(by_id['price_text']).to include('product_id' => 'prod_1', 'product_name' => 'Tokens', 'recurring_interval' => nil)
      expect(by_id['price_text_mensal']).to include('recurring_interval' => 'month')
    end
  end

  describe 'POST /super_admin/financial/token_billings/preview' do
    let(:upload) { Rack::Test::UploadedFile.new(StringIO.new(csv), 'text/csv', original_filename: 'consumo.csv') }

    # The whole point of the import: the money is shown before any invoice
    # exists, and nothing reaches Stripe while the team reconciles.
    it 'prices the spreadsheet without issuing anything' do
      expect(client).not_to receive(:create_invoice)

      post '/super_admin/financial/token_billings/preview',
           params: { file: upload, prices: { text: 'price_text', media: 'price_media', audio: 'price_audio' } }

      body = response.parsed_body
      expect(body['total_amount']).to eq(10_317)
      expect(body['lines'].first).to include('account_name' => 'Cardionorte', 'billable' => true)
    end

    it 'hands back the parsed rows so what is billed is what was reconciled' do
      post '/super_admin/financial/token_billings/preview',
           params: { file: upload, prices: { text: 'price_text', media: 'price_media', audio: 'price_audio' } }

      expect(response.parsed_body['rows'].first).to include('account_id' => account.id, 'text' => 1480)
    end

    it 'explains a spreadsheet with a missing column instead of failing blankly' do
      broken = Rack::Test::UploadedFile.new(StringIO.new("accountid,texto\n1,10\n"), 'text/csv', original_filename: 'x.csv')

      post '/super_admin/financial/token_billings/preview',
           params: { file: broken, prices: { text: 'price_text', media: 'price_media', audio: 'price_audio' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Colunas obrigatórias ausentes')
    end

    it 'asks for the prices before pricing anything' do
      post '/super_admin/financial/token_billings/preview', params: { file: upload, prices: { text: 'price_text' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Escolha o preço')
    end
  end

  describe 'POST /super_admin/financial/token_billings' do
    let(:invoice) { Struct.new(:id, :number, :hosted_invoice_url).new('in_1', 'A-001', 'https://invoice.stripe.com/x') }
    let(:payload) do
      {
        rows: [{ account_id: account.id, account_name: 'Cardionorte', text: 1480, media: 129, audio: 3 }],
        prices: { text: 'price_text', media: 'price_media', audio: 'price_audio' },
        description: 'Cobrança Tokens - Julho/2026',
        period: '2026-07'
      }
    end

    it 'issues one invoice per reconciled row' do
      expect(client).to receive(:create_invoice).with(
        hash_including(
          customer_id: 'cus_1',
          items: [{ price_id: 'price_text', quantity: 1480 }, { price_id: 'price_media', quantity: 129 },
                  { price_id: 'price_audio', quantity: 3 }],
          description: 'Cobrança Tokens - Julho/2026'
        )
      ).and_return(invoice)

      post '/super_admin/financial/token_billings', params: payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('issued_count' => 1)
      expect(response.parsed_body['results'].first).to include('status' => 'issued', 'invoice_number' => 'A-001')
    end

    # Re-picking the same three prices every month is exactly the kind of chore
    # that eventually gets picked wrong.
    it 'remembers the chosen prices for the next import' do
      allow(client).to receive(:create_invoice).and_return(invoice)

      post '/super_admin/financial/token_billings', params: payload, as: :json
      get '/super_admin/financial/token_billings/data'

      expect(response.parsed_body['selected_prices']).to include('text' => 'price_text', 'audio' => 'price_audio')
    end
  end
end
