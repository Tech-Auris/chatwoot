require 'rails_helper'

RSpec.describe 'Super Admin Financial Coupons', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  def stripe_coupon(overrides = {})
    attrs = { id: 'coupon_1', name: 'Parceiro', percent_off: 15, amount_off: nil, products: [], valid: true }.merge(overrides)
    id, name, percent_off, amount_off, products, valid = attrs.values_at(:id, :name, :percent_off, :amount_off, :products, :valid)
    applies_to = products.any? ? Struct.new(:products).new(products) : nil
    Struct.new(:id, :name, :percent_off, :amount_off, :currency, :duration, :duration_in_months,
               :times_redeemed, :max_redemptions, :valid, :applies_to)
          .new(id, name, percent_off, amount_off, 'brl', 'once', nil, 2, nil, valid, applies_to)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_coupons).and_return(Struct.new(:data).new([stripe_coupon(products: ['prod_1'])]))
    allow(client).to receive(:list_products).and_return(Struct.new(:data).new([Struct.new(:id, :name).new('prod_1', 'Plano Pro')]))
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/financial/coupons' do
    it 'renders the screen' do
      get '/super_admin/financial/coupons'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialCouponsIndex')
    end
  end

  describe 'GET /super_admin/financial/coupons/data' do
    it 'lists the coupons with the products they apply to' do
      get '/super_admin/financial/coupons/data'

      coupon = response.parsed_body['coupons'].first
      expect(coupon).to include('name' => 'Parceiro', 'percent_off' => 15, 'product_ids' => ['prod_1'])
      expect(response.parsed_body['products']).to contain_exactly(hash_including('id' => 'prod_1'))
    end

    it 'reports a coupon that applies to the whole invoice with no products' do
      allow(client).to receive(:list_coupons).and_return(Struct.new(:data).new([stripe_coupon]))

      get '/super_admin/financial/coupons/data'

      expect(response.parsed_body['coupons'].first['product_ids']).to eq([])
    end
  end

  describe 'POST /super_admin/financial/coupons' do
    it 'creates a percentage coupon' do
      expect(client).to receive(:create_coupon).with(
        hash_including(name: 'Parceiro', percent_off: '15', product_ids: ['prod_1'])
      ).and_return(stripe_coupon)

      post '/super_admin/financial/coupons',
           params: { name: 'Parceiro', percent_off: 15, duration: 'forever', product_ids: ['prod_1'] }

      expect(response).to have_http_status(:created)
    end

    # Typed in reais, charged in cents — the same trap as the invoice amounts.
    it 'converts a fixed discount from reais to cents' do
      expect(client).to receive(:create_coupon).with(hash_including(amount_off: 4990)).and_return(stripe_coupon)

      post '/super_admin/financial/coupons', params: { name: 'Cortesia', amount_off: '49.90', duration: 'once' }

      expect(response).to have_http_status(:created)
    end

    it 'reports back what Stripe refused' do
      allow(client).to receive(:create_coupon)
        .and_raise(Integrations::Stripe::Client::InvalidRequest, 'Escolha percentual ou valor, não os dois')

      post '/super_admin/financial/coupons', params: { name: 'X', percent_off: 10, amount_off: '5' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('percentual ou valor')
    end
  end

  describe 'DELETE /super_admin/financial/coupons/:id' do
    it 'deletes the coupon' do
      expect(client).to receive(:delete_coupon).with('coupon_1')

      delete '/super_admin/financial/coupons/coupon_1'

      expect(response).to have_http_status(:success)
    end
  end
end
