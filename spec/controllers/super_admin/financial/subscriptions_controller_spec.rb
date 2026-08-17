require 'rails_helper'

RSpec.describe 'Super Admin Financial Subscriptions', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  # Structs stand in for the SDK objects, which resolve their fields
  # dynamically. Note the shape: `current_period_end` hangs off the item, not
  # off the subscription, which is where this API version moved it.
  def stripe_price(unit_amount: 19_990, product: 'prod_1', interval: 'month', nickname: nil)
    recurring = interval ? Struct.new(:interval).new(interval) : nil
    Struct.new(:unit_amount, :currency, :product, :recurring, :nickname)
          .new(unit_amount, 'brl', product, recurring, nickname)
  end

  def stripe_item(id: 'si_1', quantity: 1, price: nil, current_period_end: 1_790_000_000)
    Struct.new(:id, :quantity, :price, :current_period_end)
          .new(id, quantity, price || stripe_price, current_period_end)
  end

  def stripe_subscription(id: 'sub_1', customer: 'cus_1', status: 'active', items: nil, cancel_at_period_end: false)
    item_list = Struct.new(:data).new(items || [stripe_item])
    Struct.new(:id, :customer, :status, :collection_method, :cancel_at_period_end, :items)
          .new(id, customer, status, 'send_invoice', cancel_at_period_end, item_list)
  end

  def stripe_product(id: 'prod_1', name: 'Plano Pro')
    Struct.new(:id, :name).new(id, name)
  end

  before do
    # cus_1 has a subscription below; cus_2 is reconciled but unbilled, which is
    # the case the "sem assinatura" tab exists for.
    create(:account, name: 'Clínica Conciliada', stripe_customer_id: 'cus_1')
    create(:account, name: 'Sem Assinatura', stripe_customer_id: 'cus_2')

    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_subscriptions).and_return([stripe_subscription])
    allow(client).to receive(:list_products).and_return(Struct.new(:data).new([stripe_product]))
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/financial/subscriptions' do
    it 'renders the screen' do
      get '/super_admin/financial/subscriptions'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialSubscriptionsIndex')
    end
  end

  describe 'GET /super_admin/financial/subscriptions/data' do
    it 'lists reconciled accounts with their subscription' do
      get '/super_admin/financial/subscriptions/data'

      account = response.parsed_body['accounts'].find { |row| row['name'] == 'Clínica Conciliada' }
      subscription = account['subscriptions'].first
      expect(subscription).to include('status' => 'active', 'total_amount' => 19_990, 'currency' => 'brl')
    end

    # The period moved to the subscription item in this API version; reading it
    # off the subscription would silently render "—" for every row.
    it 'reads the next billing date from the subscription item' do
      get '/super_admin/financial/subscriptions/data'

      account = response.parsed_body['accounts'].find { |row| row['name'] == 'Clínica Conciliada' }
      expect(account['subscriptions'].first['current_period_end']).to eq(1_790_000_000)
    end

    it 'resolves the product name from the catalog' do
      get '/super_admin/financial/subscriptions/data'

      account = response.parsed_body['accounts'].find { |row| row['name'] == 'Clínica Conciliada' }
      expect(account['subscriptions'].first['items'].first['product_name']).to eq('Plano Pro')
    end

    it 'multiplies the amount by the quantity' do
      allow(client).to receive(:list_subscriptions).and_return(
        [stripe_subscription(items: [stripe_item(quantity: 3)])]
      )

      get '/super_admin/financial/subscriptions/data'

      account = response.parsed_body['accounts'].find { |row| row['name'] == 'Clínica Conciliada' }
      expect(account['subscriptions'].first['total_amount']).to eq(59_970)
    end

    it 'lists reconciled accounts with no subscription, since those are the ones to chase' do
      get '/super_admin/financial/subscriptions/data'

      account = response.parsed_body['accounts'].find { |row| row['name'] == 'Sem Assinatura' }
      expect(account['subscriptions']).to be_empty
    end

    it 'never lists accounts that were not reconciled yet' do
      create(:account, name: 'Conta Pendente')

      get '/super_admin/financial/subscriptions/data'

      expect(response.parsed_body['accounts'].map { |row| row['name'] }).not_to include('Conta Pendente')
    end

    it 'filters to the accounts without a subscription' do
      get '/super_admin/financial/subscriptions/data', params: { scope: 'without_subscription' }

      expect(response.parsed_body['accounts'].map { |row| row['name'] }).to eq(['Sem Assinatura'])
      expect(response.parsed_body['meta']).to include('without_subscription_count' => 1, 'linked_count' => 2)
    end

    it 'filters by account name' do
      get '/super_admin/financial/subscriptions/data', params: { search: 'Conciliada' }

      expect(response.parsed_body['accounts'].map { |row| row['name'] }).to eq(['Clínica Conciliada'])
    end

    it 'asks the operator to configure the key when Stripe is not set up' do
      allow(client).to receive(:configured?).and_return(false)

      get '/super_admin/financial/subscriptions/data'

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Stripe Secret Key')
    end
  end
end
