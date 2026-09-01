require 'rails_helper'

RSpec.describe 'Super Admin Commercial Quotes', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:stripe_client) { instance_double(Integrations::Stripe::Client, configured?: true) }
  let(:search_service) { instance_double(Sales::ClickupProspectSearchService) }

  let(:prospect) do
    { task_id: '86ak7rd8j', name: 'Felicia Macedo', clinic_name: 'Clínica Cinco',
      email: 'contato@exemplo.com', phone: '+5561981402211', status: 'negociação' }
  end

  # `recurring: nil` stands for a one-off price; the count is what tells a
  # monthly plan from a semiannual one. `tiers` opts the price into
  # Stripe's tiered scheme, where `unit_amount` on the top level is nil.
  # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity -- test fixture, params read best inline
  def stripe_price(id: 'price_plan', product: 'prod_1', unit_amount: 89_700, active: true,
                   recurring: { interval: 'month', count: 1 }, tiers: nil)
    recurring &&= Struct.new(:interval, :interval_count).new(recurring[:interval], recurring[:count] || 1)
    tier_struct = Struct.new(:up_to, :unit_amount, :flat_amount, keyword_init: true)
    tiers_data = tiers&.map { |band| tier_struct.new(**band) }
    scheme = tiers ? 'tiered' : 'per_unit'
    Struct.new(:id, :product, :unit_amount, :currency, :recurring, :active, :nickname,
               :billing_scheme, :tiers_mode, :tiers)
          .new(id, product, tiers ? nil : unit_amount, 'brl', recurring, active, nil,
               scheme, tiers ? 'graduated' : nil, tiers_data)
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/CyclomaticComplexity

  def stripe_product(id: 'prod_1', name: 'Plano Pro', description: nil, metadata: {})
    Struct.new(:id, :name, :description, :metadata).new(id, name, description, metadata)
  end

  def stub_catalog(prices:, products: [stripe_product])
    allow(stripe_client).to receive(:list_prices).and_return(Struct.new(:data).new(prices))
    allow(stripe_client).to receive(:list_products).and_return(Struct.new(:data).new(products))
  end

  def catalog_from_data
    get '/super_admin/commercial/quotes/data'
    response.parsed_body['prices']
  end

  def stripe_coupon(id: 'coupon_1', percent_off: 15, valid: true)
    Struct.new(:id, :name, :percent_off, :amount_off, :currency, :valid)
          .new(id, 'Parceiro', percent_off, nil, 'brl', valid)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
    allow(Sales::ClickupProspectSearchService).to receive(:new).and_return(search_service)
    allow(stripe_client).to receive(:list_prices).and_return(Struct.new(:data).new([stripe_price]))
    allow(stripe_client).to receive(:list_products).and_return(Struct.new(:data).new([stripe_product]))
    allow(stripe_client).to receive(:list_coupons).and_return(Struct.new(:data).new([stripe_coupon]))
    allow(search_service).to receive(:find).with('86ak7rd8j').and_return(prospect)
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/commercial/quotes' do
    it 'renders the screen' do
      get '/super_admin/commercial/quotes'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('CommercialQuotesIndex')
    end
  end

  describe 'the catalogue offered to the seller' do
    # Archiving a product in Stripe does not archive its prices, so filtering
    # the price alone kept retired plans on sale here.
    it 'leaves out the price of a product that is no longer sold' do
      stub_catalog(prices: [stripe_price, stripe_price(id: 'price_old', product: 'prod_retired')])

      expect(catalog_from_data.pluck('id')).to eq(['price_plan'])
    end

    it 'leaves out an archived price of a product still on sale' do
      stub_catalog(prices: [stripe_price, stripe_price(id: 'price_old', active: false)])

      expect(catalog_from_data.pluck('id')).to eq(['price_plan'])
    end

    # Stripe describes a semiannual plan as six monthly intervals.
    it 'reads the billing period from the interval and its count' do
      stub_catalog(prices: [stripe_price(id: 'p_month'),
                            stripe_price(id: 'p_semi', recurring: { interval: 'month', count: 6 }),
                            stripe_price(id: 'p_year', recurring: { interval: 'year' }),
                            stripe_price(id: 'p_once', recurring: nil)])

      periods = catalog_from_data.to_h { |price| [price['id'], price['billing_period']] }
      expect(periods).to eq('p_month' => 'monthly', 'p_semi' => 'semiannual',
                            'p_year' => 'annual', 'p_once' => 'one_off')
    end

    it 'takes a recurring price for the plan and a one-off for an extra' do
      stub_catalog(prices: [stripe_price(id: 'p_plan'), stripe_price(id: 'p_extra', recurring: nil)])

      categories = catalog_from_data.to_h { |price| [price['id'], price['category']] }
      expect(categories).to eq('p_plan' => 'plan', 'p_extra' => 'addon')
    end

    # A recurring extra — a second number billed monthly — is a plan by that
    # rule alone, so Stripe gets the final word.
    # The picker groups by product and shows the description beside each
    # price, so the description has to travel from Stripe through the
    # catalogue payload without being dropped.
    it 'carries the product description so the picker can show it beside each price' do
      stub_catalog(prices: [stripe_price],
                   products: [stripe_product(description: 'Inclui 1 Unidade, 1 Profissional de Atendimento')])

      expect(catalog_from_data.first['product_description']).to eq('Inclui 1 Unidade, 1 Profissional de Atendimento')
    end

    # A tiered Stripe price has no top-level unit amount, so the row
    # falls back to the first tier and the UI labels it "a partir de".
    # Without this the picker read R$ 0,00 on every tiered plan.
    it 'reads a tiered price from the first tier and flags it as "starts from"' do
      stub_catalog(prices: [stripe_price(tiers: [{ up_to: 8, unit_amount: 5_900, flat_amount: nil },
                                                 { up_to: nil, unit_amount: 900, flat_amount: nil }])])

      row = catalog_from_data.first
      expect(row).to include('tiered' => true, 'starting_amount' => 5_900, 'unit_amount' => nil)
    end

    it 'lets the product say what it is' do
      stub_catalog(prices: [stripe_price(product: 'prod_extra')],
                   products: [stripe_product(id: 'prod_extra', name: 'Número extra',
                                             metadata: { 'auris_category' => 'addon' })])

      expect(catalog_from_data.first['category']).to eq('addon')
    end

    # The catalogue grows and the team sells a handful of combinations.
    it 'puts what has been sold most at the top' do
      quote = create(:sales_quote)
      create(:sales_quote_item, sales_quote: quote, stripe_price_id: 'price_used')
      create(:sales_quote_item, sales_quote: quote, stripe_price_id: 'price_used')
      create(:sales_quote_item, sales_quote: quote, stripe_price_id: 'price_rare')
      stub_catalog(prices: [stripe_price(id: 'price_never'), stripe_price(id: 'price_rare'),
                            stripe_price(id: 'price_used')])

      catalog = catalog_from_data
      expect(catalog.pluck('id')).to eq(%w[price_used price_rare price_never])
      expect(catalog.first['usage_count']).to eq(2)
    end
  end

  describe 'GET /super_admin/commercial/quotes/data' do
    it 'offers the catalogue and the valid coupons' do
      get '/super_admin/commercial/quotes/data'

      body = response.parsed_body
      expect(body['prices'].first).to include('id' => 'price_plan', 'product_name' => 'Plano Pro')
      expect(body['coupons'].first).to include('id' => 'coupon_1')
      expect(body['meeting_discount_percent']).to eq(10)
    end

    it 'leaves out a coupon Stripe no longer considers valid' do
      allow(stripe_client).to receive(:list_coupons).and_return(Struct.new(:data).new([stripe_coupon(valid: false)]))

      get '/super_admin/commercial/quotes/data'

      expect(response.parsed_body['coupons']).to be_empty
    end
  end

  describe 'GET /super_admin/commercial/quotes/prospects' do
    it 'searches the pipeline' do
      expect(search_service).to receive(:search).with('felicia').and_return([prospect])

      get '/super_admin/commercial/quotes/prospects', params: { q: 'felicia' }

      expect(response.parsed_body['prospects'].first).to include('task_id' => '86ak7rd8j')
    end

    it 'explains itself when the pipeline list was never configured' do
      allow(search_service).to receive(:search).and_raise(Sales::ClickupProspectSearchService::NotConfigured, 'Configure a lista do pipeline')

      get '/super_admin/commercial/quotes/prospects', params: { q: 'x' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('pipeline')
    end
  end

  describe 'POST /super_admin/commercial/quotes/preview' do
    # The seller watches this number move during the meeting, so it is priced
    # without writing anything down.
    it 'prices the cart without creating a proposal' do
      expect do
        post '/super_admin/commercial/quotes/preview',
             params: { items: [{ unit_amount: 89_700, quantity: 1 }], meeting_discount: true, coupon_id: 'coupon_1' },
             as: :json
      end.not_to change(SalesQuote, :count)

      body = response.parsed_body
      expect(body).to include('subtotal' => 89_700, 'discount' => 8970 + 13_455)
      expect(body['summary']).to eq('10% reunião + cupom Parceiro (15%)')
    end
  end

  describe 'POST /super_admin/commercial/quotes' do
    let(:payload) do
      {
        clickup_task_id: '86ak7rd8j',
        meeting_discount: true,
        items: [{ stripe_price_id: 'price_plan', stripe_product_id: 'prod_1', name: 'Plano Pro',
                  unit_amount: 89_700, quantity: 1, recurring_interval: 'month',
                  billing_period: 'annual', kind: 'plan' }]
      }
    end

    it 'creates the proposal with the prospect taken from ClickUp' do
      post '/super_admin/commercial/quotes', params: payload, as: :json

      expect(response).to have_http_status(:created)
      quote = SalesQuote.last
      # The task title is the person; the clinic rides in its own field and is
      # usually still blank at this point.
      expect(quote).to have_attributes(
        clickup_task_id: '86ak7rd8j', prospect_name: 'Felicia Macedo', company_name: 'Clínica Cinco',
        prospect_phone: '+5561981402211', clickup_status: 'negociação', status: 'draft'
      )
    end

    # The catalogue moves; what the prospect was shown must not move with it.
    it 'freezes the amounts and the discount breakdown on the proposal' do
      post '/super_admin/commercial/quotes', params: payload, as: :json

      quote = SalesQuote.last
      expect(quote).to have_attributes(subtotal_amount: 89_700, discount_amount: 8970, total_amount: 80_730,
                                       discount_summary: '10% reunião')
      expect(quote.items.first).to have_attributes(name: 'Plano Pro', unit_amount: 89_700)
    end

    it 'issues the credentials the prospect will need' do
      post '/super_admin/commercial/quotes', params: payload, as: :json

      body = response.parsed_body['quote']
      expect(body['access_code']).to match(/\A\d{6}\z/)
      expect(body['public_token']).to be_present
      expect(SalesQuote.last.verification_phone_last4).to eq('2211')
    end

    it 'records who created it' do
      post '/super_admin/commercial/quotes', params: payload, as: :json

      expect(SalesQuote.last.events.first).to have_attributes(event: 'created', user_id: super_admin.id)
    end

    # Checkout routes the card between Stripe (monthly, subscription) and
    # AsaaS (semi/annual, instalments) by the quote's billing_cycle, so the
    # plan item's billing_period has to land there at creation.
    it 'takes the billing cycle from the plan item so checkout can route the card' do
      post '/super_admin/commercial/quotes',
           params: payload.deep_merge(items: [payload[:items].first.merge(billing_period: 'monthly')]),
           as: :json

      expect(SalesQuote.last.billing_cycle).to eq('monthly')
    end

    it 'still writes the billing cycle when the plan is annual' do
      post '/super_admin/commercial/quotes', params: payload, as: :json

      expect(SalesQuote.last.billing_cycle).to eq('annual')
    end

    # A stray `billing_period` on a payload — an addon-only cart, or a value
    # outside the enum — must not blow up the create with an enum error.
    it 'leaves the billing cycle blank when no plan item declares one' do
      addon_only = payload.merge(
        items: [{ stripe_price_id: 'price_setup', name: 'Setup', unit_amount: 50_000, quantity: 1, kind: 'addon' }]
      )

      post '/super_admin/commercial/quotes', params: addon_only, as: :json

      expect(response).to have_http_status(:created)
      expect(SalesQuote.last.billing_cycle).to be_nil
    end
  end

  describe 'POST /super_admin/commercial/quotes/:id/reserve' do
    let(:clickup_client) { instance_double(Integrations::Clickup::Client, configured?: true) }
    let(:quote) { create(:sales_quote) }

    before do
      allow(Integrations::Clickup::Client).to receive(:new).and_return(clickup_client)
      allow(clickup_client).to receive(:update_task)
      allow(clickup_client).to receive(:add_tag)
    end

    it 'holds the proposal and answers with the link and the QR the seller shares' do
      post "/super_admin/commercial/quotes/#{quote.id}/reserve",
           params: { reserved_until: 5.days.from_now.iso8601 }, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body['quote']
      expect(body['public_url']).to include("/proposals/#{quote.public_token}")
      expect(body['qr_code']).to start_with('data:image/svg+xml;base64,')
      expect(quote.reload.status).to eq('reserved')
    end

    # The seller is in front of the customer; a ClickUp outage cannot block the
    # reservation, but it also cannot pass silently.
    it 'reports a ClickUp failure without losing the reservation' do
      allow(clickup_client).to receive(:add_tag).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'ClickUp 503')

      post "/super_admin/commercial/quotes/#{quote.id}/reserve",
           params: { reserved_until: 5.days.from_now.iso8601 }, as: :json

      expect(response.parsed_body).to include('clickup_synced' => false, 'clickup_error' => 'ClickUp 503')
      expect(quote.reload.status).to eq('reserved')
    end

    it 'refuses a date in the past' do
      post "/super_admin/commercial/quotes/#{quote.id}/reserve",
           params: { reserved_until: 2.days.ago.iso8601 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('futuro')
    end
  end

  describe 'the pipeline list configuration' do
    # The search cannot guess which ClickUp list holds the pipeline, and a wrong
    # guess would silently search the wrong deals.
    it 'is offered on the ClickUp settings screen' do
      get '/super_admin/app_config', params: { config: 'clickup' }

      expect(response.body).to include('CLICKUP_PIPELINE_LIST_ID')
    end
  end
end
