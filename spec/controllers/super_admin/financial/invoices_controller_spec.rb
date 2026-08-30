require 'rails_helper'

RSpec.describe 'Super Admin Financial Invoices', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  # In this API version the price of an invoice line hangs off
  # `pricing.price_details`, not `line.price`.
  def stripe_line(product: 'prod_1', description: '1 × Plano Pro')
    price_details = product ? Struct.new(:product).new(product) : nil
    pricing = Struct.new(:price_details).new(price_details)
    Struct.new(:description, :pricing).new(description, pricing)
  end

  # Stands in for the SDK object, whose fields resolve dynamically.
  def stripe_invoice(overrides = {})
    attrs = { id: 'in_1', customer: 'cus_1', status: 'open', due_date: 1_790_000_000, metadata: {}, lines: nil }.merge(overrides)
    line_list = Struct.new(:data).new(attrs[:lines] || [stripe_line])

    Struct.new(
      :id, :number, :status, :customer, :customer_name, :amount_due, :amount_paid,
      :currency, :due_date, :created, :hosted_invoice_url, :invoice_pdf, :metadata, :lines
    ).new(
      attrs[:id], 'A-001', attrs[:status], attrs[:customer], 'Clínica no Stripe', 19_990, 0,
      'brl', attrs[:due_date], 1_789_000_000, 'https://invoice.stripe.com/x', 'https://invoice.stripe.com/x.pdf',
      attrs[:metadata], line_list
    )
  end

  def stripe_product(id: 'prod_1', name: 'Plano Pro')
    Struct.new(:id, :name).new(id, name)
  end

  def stripe_catalog_price(id: 'price_1', product: 'prod_1', active: true, interval: nil)
    recurring = interval ? Struct.new(:interval).new(interval) : nil
    Struct.new(:id, :product, :unit_amount, :currency, :recurring, :active, :nickname)
          .new(id, product, 15_000, 'brl', recurring, active, nil)
  end

  def stripe_list(invoices, has_more: false)
    Struct.new(:data, :has_more).new(invoices, has_more)
  end

  before do
    create(:account, name: 'Clínica Conciliada', stripe_customer_id: 'cus_1')
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_invoices).and_return(stripe_list([stripe_invoice]))
    allow(client).to receive(:list_products).and_return(Struct.new(:data).new([stripe_product]))
    allow(client).to receive(:list_prices).and_return(Struct.new(:data).new([stripe_catalog_price]))
    allow(client).to receive(:list_coupons).and_return(
      Struct.new(:data).new([Struct.new(:id, :name, :percent_off, :amount_off, :currency, :duration, :valid)
                                   .new('coupon_1', 'Parceiro', 15, nil, 'brl', 'once', true)])
    )
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'searching for a customer' do
    let(:stripe_customer) { Struct.new(:id, :name, :email).new('cus_2', 'Felicia Macedo', 'felicia@exemplo.com') }

    before do
      allow(client).to receive(:search_customers).and_return([stripe_customer])
      allow(client).to receive(:list_invoices).with(hash_including(customer_id: 'cus_2'))
                                              .and_return(stripe_list([stripe_invoice(id: 'in_felicia', customer: 'cus_2')]))
      allow(client).to receive(:list_invoices).with(hash_including(customer_id: 'cus_1'))
                                              .and_return(stripe_list([stripe_invoice(id: 'in_conciliada')]))
    end

    it 'lists the invoices of whoever matches the term in stripe' do
      get '/super_admin/financial/invoices/data', params: { q: 'felicia' }

      expect(client).to have_received(:search_customers).with('felicia')
      expect(response.parsed_body['invoices'].pluck('id')).to eq(['in_felicia'])
    end

    # An account renamed here keeps the name it was sold under in Stripe, so the
    # term is matched against our own names too.
    it 'finds a customer by the account name even when stripe has another' do
      allow(client).to receive(:search_customers).and_return([])

      get '/super_admin/financial/invoices/data', params: { q: 'conciliada' }

      expect(response.parsed_body['invoices'].pluck('id')).to eq(['in_conciliada'])
    end

    it 'keeps the status tab while searching' do
      get '/super_admin/financial/invoices/data', params: { q: 'felicia', status: 'paid' }

      expect(client).to have_received(:list_invoices).with(hash_including(status: 'paid', customer_id: 'cus_2'))
    end

    it 'answers with nothing when the term matches no customer' do
      allow(client).to receive(:search_customers).and_return([])

      get '/super_admin/financial/invoices/data', params: { q: 'ninguem' }

      expect(response.parsed_body['invoices']).to be_empty
      expect(response.parsed_body['meta']['has_more']).to be(false)
    end

    # The search answers with one page of that customer's invoices; paging the
    # whole account is what the unfiltered list is for.
    it 'does not offer another page of results' do
      get '/super_admin/financial/invoices/data', params: { q: 'felicia' }

      expect(response.parsed_body['meta']['has_more']).to be(false)
    end
  end

  describe 'GET /super_admin/financial/invoices' do
    it 'renders the screen' do
      get '/super_admin/financial/invoices'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialInvoicesIndex')
    end

    # The screen builds the write-off URL by appending the invoice id, so a base
    # that stops routing would only fail when someone settles a real invoice.
    it 'hands the screen a base URL that still routes once an id is appended' do
      get '/super_admin/financial/invoices'

      props = JSON.parse(Nokogiri::HTML(response.body).at_css('#app')['data-props'])
      member_path = URI.parse("#{props['invoices_url']}/in_123/pay").path

      expect(Rails.application.routes.recognize_path(member_path, method: :post))
        .to include(controller: 'super_admin/financial/invoices', action: 'pay')
    end
  end

  describe 'GET /super_admin/financial/invoices/data' do
    it 'lists invoices with the account behind the Stripe customer' do
      get '/super_admin/financial/invoices/data'

      invoice = response.parsed_body['invoices'].first
      expect(invoice).to include(
        'id' => 'in_1', 'status' => 'open', 'amount_due' => 19_990, 'account_name' => 'Clínica Conciliada'
      )
    end

    # Every row of the page has to resolve its own account: a lookup memoized on
    # the first customer would label the whole page with one clinic's name.
    it 'resolves the account of every invoice on the page' do
      create(:account, name: 'Outra Clínica', stripe_customer_id: 'cus_2')
      allow(client).to receive(:list_invoices).and_return(
        stripe_list([stripe_invoice(id: 'in_1', customer: 'cus_1'), stripe_invoice(id: 'in_2', customer: 'cus_2')])
      )

      get '/super_admin/financial/invoices/data'

      expect(response.parsed_body['invoices'].pluck('account_name')).to eq(['Clínica Conciliada', 'Outra Clínica'])
    end

    it 'leaves the account blank for a customer nobody reconciled yet' do
      allow(client).to receive(:list_invoices).and_return(stripe_list([stripe_invoice(customer: 'cus_sem_vinculo')]))

      get '/super_admin/financial/invoices/data'

      expect(response.parsed_body['invoices'].first['account_name']).to be_nil
    end

    it 'passes the status filter and the cursor through to Stripe' do
      expect(client).to receive(:list_invoices).with(status: 'open', starting_after: 'in_9').and_return(stripe_list([]))

      get '/super_admin/financial/invoices/data', params: { status: 'open', starting_after: 'in_9' }

      expect(response).to have_http_status(:success)
    end

    it 'reports the cursor of the last row so the next page can be asked for' do
      allow(client).to receive(:list_invoices).and_return(stripe_list([stripe_invoice(id: 'in_7')], has_more: true))

      get '/super_admin/financial/invoices/data'

      expect(response.parsed_body['meta']).to include('has_more' => true, 'last_id' => 'in_7')
    end

    describe 'the product each invoice charges for' do
      it 'names the product behind the invoice line' do
        get '/super_admin/financial/invoices/data'

        expect(response.parsed_body['invoices'].first['products']).to eq(['Plano Pro'])
      end

      # A product archived out of the catalog still has to say what was billed —
      # the line description is what Stripe itself prints on the invoice.
      it 'falls back to the line description when the product is gone' do
        allow(client).to receive(:list_invoices).and_return(
          stripe_list([stripe_invoice(lines: [stripe_line(product: 'prod_removido', description: '1 × Plano antigo')])])
        )

        get '/super_admin/financial/invoices/data'

        expect(response.parsed_body['invoices'].first['products']).to eq(['1 × Plano antigo'])
      end

      it 'lists each distinct product of a multi-line invoice once' do
        allow(client).to receive(:list_products).and_return(
          Struct.new(:data).new([stripe_product, stripe_product(id: 'prod_2', name: 'Mensagens extras')])
        )
        allow(client).to receive(:list_invoices).and_return(
          stripe_list([stripe_invoice(lines: [stripe_line, stripe_line, stripe_line(product: 'prod_2')])])
        )

        get '/super_admin/financial/invoices/data'

        expect(response.parsed_body['invoices'].first['products']).to eq(['Plano Pro', 'Mensagens extras'])
      end
    end

    it 'surfaces the payment origin already recorded on an invoice' do
      allow(client).to receive(:list_invoices).and_return(
        stripe_list([stripe_invoice(status: 'paid', metadata: { 'aurischat_paid_via' => 'asaas' })])
      )

      get '/super_admin/financial/invoices/data'

      expect(response.parsed_body['invoices'].first['paid_via']).to eq('asaas')
    end
  end

  describe 'POST /super_admin/financial/invoices' do
    let(:account) { Account.find_by(name: 'Clínica Conciliada') }

    it 'issues an invoice with a catalog item for the account customer' do
      expect(client).to receive(:create_invoice).with(
        customer_id: 'cus_1',
        items: [{ price_id: 'price_1', quantity: 2, description: nil, unit_amount: nil }],
        days_until_due: 7,
        description: nil,
        coupon_id: nil
      ).and_return(stripe_invoice)

      post '/super_admin/financial/invoices',
           params: { account_id: account.id, items: [{ price_id: 'price_1', quantity: 2 }] }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['invoice']).to include('id' => 'in_1', 'account_name' => 'Clínica Conciliada')
    end

    # Operators type reais; Stripe counts cents. Getting this wrong bills a
    # customer a hundred times over.
    it 'converts a free amount from reais to cents' do
      expect(client).to receive(:create_invoice).with(
        hash_including(items: [{ price_id: nil, quantity: 3, description: 'Tokens de agosto', unit_amount: 12_990 }])
      ).and_return(stripe_invoice)

      post '/super_admin/financial/invoices',
           params: {
             account_id: account.id,
             items: [{ description: 'Tokens de agosto', amount: '129.90', quantity: 3 }]
           }

      expect(response).to have_http_status(:created)
    end

    it 'drops the blank rows the form always carries' do
      expect(client).to receive(:create_invoice).with(
        hash_including(items: [hash_including(price_id: 'price_1')])
      ).and_return(stripe_invoice)

      post '/super_admin/financial/invoices',
           params: { account_id: account.id, items: [{ price_id: 'price_1' }, { price_id: '', amount: '' }] }

      expect(response).to have_http_status(:created)
    end

    it 'passes the due window chosen by the operator' do
      expect(client).to receive(:create_invoice).with(hash_including(days_until_due: 20)).and_return(stripe_invoice)

      post '/super_admin/financial/invoices',
           params: { account_id: account.id, days_until_due: 20, items: [{ price_id: 'price_1' }] }

      expect(response).to have_http_status(:created)
    end

    it 'applies the coupon chosen by the operator' do
      expect(client).to receive(:create_invoice).with(hash_including(coupon_id: 'coupon_1')).and_return(stripe_invoice)

      post '/super_admin/financial/invoices',
           params: { account_id: account.id, items: [{ price_id: 'price_1' }], coupon_id: 'coupon_1' }

      expect(response).to have_http_status(:created)
    end

    it 'refuses an account with no Stripe customer' do
      unlinked = create(:account, name: 'Sem Vínculo')

      post '/super_admin/financial/invoices', params: { account_id: unlinked.id, items: [{ price_id: 'price_1' }] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('sem cliente do Stripe')
    end

    it 'reports back what Stripe refused' do
      allow(client).to receive(:create_invoice)
        .and_raise(Integrations::Stripe::Client::InvalidRequest, 'No such price: price_1')

      post '/super_admin/financial/invoices', params: { account_id: account.id, items: [{ price_id: 'price_1' }] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('No such price: price_1')
    end
  end

  describe 'the data payload backing the new-invoice form' do
    it 'lists the accounts that can be billed and the active catalog prices' do
      create(:account, name: 'Sem Vínculo')

      get '/super_admin/financial/invoices/data'

      body = response.parsed_body
      expect(body['accounts'].pluck('name')).to eq(['Clínica Conciliada'])
      expect(body['prices']).to contain_exactly(hash_including('id' => 'price_1', 'product_name' => 'Plano Pro'))
    end

    it 'leaves archived prices out of the picker' do
      allow(client).to receive(:list_prices).and_return(
        Struct.new(:data).new([stripe_catalog_price(id: 'price_velho', active: false)])
      )

      get '/super_admin/financial/invoices/data'

      expect(response.parsed_body['prices']).to be_empty
    end
  end

  describe 'POST /super_admin/financial/invoices/:id/pay' do
    it 'writes the invoice off with the origin the operator chose' do
      expect(client).to receive(:pay_invoice_out_of_band)
        .with('in_1', paid_via: 'inter')
        .and_return(stripe_invoice(status: 'paid', metadata: { 'aurischat_paid_via' => 'inter' }))

      post '/super_admin/financial/invoices/in_1/pay', params: { paid_via: 'inter' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['invoice']).to include('status' => 'paid', 'paid_via' => 'inter')
    end

    it 'reports back what Stripe refused' do
      allow(client).to receive(:pay_invoice_out_of_band)
        .and_raise(Integrations::Stripe::Client::InvalidRequest, 'Invoice is already paid')

      post '/super_admin/financial/invoices/in_1/pay', params: { paid_via: 'inter' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Invoice is already paid')
    end
  end
end
