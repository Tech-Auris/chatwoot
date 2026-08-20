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

  def stripe_list(invoices, has_more: false)
    Struct.new(:data, :has_more).new(invoices, has_more)
  end

  before do
    create(:account, name: 'Clínica Conciliada', stripe_customer_id: 'cus_1')
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_invoices).and_return(stripe_list([stripe_invoice]))
    allow(client).to receive(:list_products).and_return(Struct.new(:data).new([stripe_product]))
    sign_in(super_admin, scope: :super_admin)
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
