require 'rails_helper'

RSpec.describe 'Super Admin Financial Products', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  # Stripe SDK objects respond to their fields dynamically, so verifying
  # doubles have nothing to verify against — plain structs stand in for the
  # slices of the response the controller reads.
  def stripe_list(data)
    Struct.new(:data).new(data)
  end

  def stripe_price(id: 'price_1', product: 'prod_1', unit_amount: 19_990, active: true, interval: 'month')
    recurring = interval ? Struct.new(:interval).new(interval) : nil
    Struct.new(:id, :product, :unit_amount, :currency, :active, :recurring)
          .new(id, product, unit_amount, 'brl', active, recurring)
  end

  def stripe_product(id: 'prod_1', name: 'Plano Pro', active: true)
    Struct.new(:id, :name, :description, :active, :created)
          .new(id, name, 'Assinatura mensal', active, 1_786_740_060)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
  end

  describe 'GET /super_admin/financial/products' do
    it 'redirects an unauthenticated visitor' do
      get '/super_admin/financial/products'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the screen for a signed in super admin' do
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/financial/products'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialProductsIndex')
    end

    # Same trap as the customer links screen: the member URLs are built by
    # appending the product id to `products_url`, so a `.json` suffix on the
    # base would route nowhere on edit, archive and new price.
    it 'hands the screen a base URL that still routes once an id is appended' do
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/financial/products'

      props = JSON.parse(Nokogiri::HTML(response.body).at_css('#app')['data-props'])
      member_path = URI.parse("#{props['products_url']}/prod_123").path

      expect(Rails.application.routes.recognize_path(member_path, method: :patch))
        .to include(controller: 'super_admin/financial/products', action: 'update')
      expect(Rails.application.routes.recognize_path("#{member_path}/prices", method: :post))
        .to include(controller: 'super_admin/financial/products', action: 'prices')
    end
  end

  describe 'GET /super_admin/financial/products/data' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'lists the Stripe catalog with the prices grouped per product' do
      allow(client).to receive(:list_products).and_return(stripe_list([stripe_product]))
      allow(client).to receive(:list_prices).and_return(stripe_list([stripe_price]))

      get '/super_admin/financial/products/data'

      expect(response).to have_http_status(:success)
      product = response.parsed_body['products'].first
      expect(product['id']).to eq('prod_1')
      expect(product['prices'].first).to include('id' => 'price_1', 'unit_amount' => 19_990, 'recurring_interval' => 'month')
    end

    it 'asks the operator to configure the key when Stripe is not set up' do
      allow(client).to receive(:configured?).and_return(false)

      get '/super_admin/financial/products/data'

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Stripe Secret Key')
    end

    it 'surfaces an invalid credential as unauthorized' do
      allow(client).to receive(:list_products).and_raise(Integrations::Stripe::Client::Unauthorized, 'bad key')

      get '/super_admin/financial/products/data'

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to include('bad key')
    end
  end

  describe 'POST /super_admin/financial/products' do
    before do
      sign_in(super_admin, scope: :super_admin)
      allow(client).to receive(:list_prices).and_return(stripe_list([]))
    end

    it 'creates the product without a price when no amount is given' do
      allow(client).to receive(:create_product).and_return(stripe_product)
      allow(client).to receive(:create_price)

      post '/super_admin/financial/products', params: { product: { name: 'Plano Pro', description: 'Assinatura mensal' } }

      expect(response).to have_http_status(:created)
      expect(client).to have_received(:create_product).with(name: 'Plano Pro', description: 'Assinatura mensal', active: true)
      expect(client).not_to have_received(:create_price)
    end

    it 'creates the first price along with the product when an amount is given' do
      allow(client).to receive(:create_product).and_return(stripe_product)
      allow(client).to receive(:create_price).and_return(stripe_price)

      post '/super_admin/financial/products',
           params: { product: { name: 'Plano Pro' }, price: { unit_amount: 19_990, currency: 'brl', recurring_interval: 'month' } }

      expect(response).to have_http_status(:created)
      expect(client).to have_received(:create_price).with(
        product_id: 'prod_1', unit_amount: 19_990, currency: 'brl', recurring_interval: 'month'
      )
    end
  end

  describe 'PATCH /super_admin/financial/products/:id' do
    before do
      sign_in(super_admin, scope: :super_admin)
      allow(client).to receive(:list_prices).and_return(stripe_list([]))
    end

    it 'updates the editable fields' do
      allow(client).to receive(:update_product).and_return(stripe_product(name: 'Plano Enterprise'))

      patch '/super_admin/financial/products/prod_1', params: { product: { name: 'Plano Enterprise' } }

      expect(response).to have_http_status(:success)
      expect(client).to have_received(:update_product).with('prod_1', { name: 'Plano Enterprise' })
    end

    it 'casts the active flag coming from JSON as a boolean' do
      allow(client).to receive(:update_product).and_return(stripe_product)

      patch '/super_admin/financial/products/prod_1', params: { product: { active: 'true' } }

      expect(client).to have_received(:update_product).with('prod_1', { active: true })
    end
  end

  describe 'DELETE /super_admin/financial/products/:id' do
    before do
      sign_in(super_admin, scope: :super_admin)
      allow(client).to receive(:list_prices).and_return(stripe_list([]))
    end

    it 'archives the product instead of deleting it' do
      allow(client).to receive(:archive_product).and_return(stripe_product(active: false))

      delete '/super_admin/financial/products/prod_1'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['product']['active']).to be false
      expect(client).to have_received(:archive_product).with('prod_1')
    end
  end

  describe 'POST /super_admin/financial/products/:id/prices' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'creates a new price for the product' do
      allow(client).to receive(:create_price).and_return(stripe_price(id: 'price_2', unit_amount: 29_990))

      post '/super_admin/financial/products/prod_1/prices',
           params: { price: { unit_amount: 29_990, currency: 'brl', recurring_interval: 'month' } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['price']).to include('id' => 'price_2', 'unit_amount' => 29_990)
    end

    it 'defaults the currency to brl' do
      allow(client).to receive(:create_price).and_return(stripe_price)

      post '/super_admin/financial/products/prod_1/prices', params: { price: { unit_amount: 5000 } }

      expect(client).to have_received(:create_price).with(
        product_id: 'prod_1', unit_amount: 5000, currency: 'brl', recurring_interval: nil
      )
    end
  end
end
