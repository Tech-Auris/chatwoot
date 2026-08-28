require 'rails_helper'

RSpec.describe 'Super Admin Financial Pix Renewals', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }
  let(:account) { create(:account, name: 'Clínica Cinco', stripe_customer_id: 'cus_1') }
  let(:quote) do
    create(:sales_quote, status: :converted, payment_method: :pix, billing_cycle: :monthly,
                         total_amount: 89_700, company_name: 'Clínica Cinco', account: account)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/financial/pix_renewals' do
    it 'renders the screen' do
      get '/super_admin/financial/pix_renewals'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialPixRenewalsIndex')
    end
  end

  describe 'GET /super_admin/financial/pix_renewals/data' do
    let!(:due_soon) { create(:pix_renewal, account: account, sales_quote: quote, due_on: 3.days.from_now.to_date) }
    let!(:overdue) { create(:pix_renewal, account: account, sales_quote: quote, due_on: 2.days.ago.to_date, status: :invoiced) }
    let!(:settled) { create(:pix_renewal, account: account, sales_quote: quote, due_on: 1.month.ago.to_date, status: :paid, paid_at: 1.month.ago) }

    it 'lists the open periods by due date and counts what needs attention' do
      get '/super_admin/financial/pix_renewals/data'

      expect(response.parsed_body['renewals'].pluck('id')).to eq([overdue.id, due_soon.id])
      expect(response.parsed_body['meta']).to include('alert_count' => 2, 'overdue_count' => 1, 'alert_window_days' => 7)
    end

    it 'flags what is late and what is about to come due' do
      get '/super_admin/financial/pix_renewals/data'

      rows = response.parsed_body['renewals'].index_by { |row| row['id'] }
      expect(rows[overdue.id]).to include('overdue' => true)
      expect(rows[due_soon.id]).to include('overdue' => false, 'alerting' => true,
                                           'reference_month' => 3.days.from_now.strftime('%m/%Y'))
    end

    it 'keeps the settled periods out of the open tab' do
      get '/super_admin/financial/pix_renewals/data', params: { status: 'paid' }

      expect(response.parsed_body['renewals'].pluck('id')).to eq([settled.id])
    end

    # A PIX sale sits at "signed" until somebody confirms the money.
    it 'lists the sales still waiting for their first payment' do
      waiting = create(:sales_quote, status: :signed, payment_method: :pix, company_name: 'Clínica Nova', total_amount: 50_000)
      create(:sales_quote, status: :signed, payment_method: :card, company_name: 'Paga no cartão')

      get '/super_admin/financial/pix_renewals/data'

      expect(response.parsed_body['awaiting_first_payment'].pluck('id')).to eq([waiting.id])
    end
  end

  describe 'actions on a period' do
    let(:renewal) { create(:pix_renewal, account: account, sales_quote: quote, due_on: 4.days.from_now.to_date) }

    it 'issues the invoice' do
      allow(client).to receive(:create_invoice).and_return(Struct.new(:id, :hosted_invoice_url).new('in_1', 'https://invoice.stripe.com/x'))

      post "/super_admin/financial/pix_renewals/#{renewal.id}/invoice"

      expect(response.parsed_body['renewal']).to include('status' => 'invoiced')
    end

    it 'writes the invoice off and opens the next period' do
      renewal.update!(status: :invoiced, stripe_invoice_id: 'in_1')
      allow(client).to receive(:pay_invoice_out_of_band)

      post "/super_admin/financial/pix_renewals/#{renewal.id}/pay", params: { paid_via: 'inter' }

      expect(response.parsed_body['renewal']).to include('status' => 'paid', 'paid_via' => 'inter')
      expect(PixRenewal.status_pending.last.due_on).to eq(renewal.due_on + 1.month)
    end

    it 'answers with the reason when the period cannot move' do
      post "/super_admin/financial/pix_renewals/#{renewal.id}/pay", params: { paid_via: 'inter' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Gere a fatura/)
    end

    it 'ends the billing of a customer who left' do
      post "/super_admin/financial/pix_renewals/#{renewal.id}/cancel"

      expect(renewal.reload.status).to eq('cancelled')
    end
  end

  describe 'POST /super_admin/financial/pix_renewals/register_sale' do
    let(:waiting) do
      create(:sales_quote, status: :signed, payment_method: :pix, billing_cycle: :annual,
                           total_amount: 900_000, company_name: 'Clínica Nova', prospect_email: 'nova@exemplo.com')
    end

    before do
      allow(client).to receive_messages(create_customer: Struct.new(:id).new('cus_9'), create_invoice: Struct.new(:id).new('in_9'))
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:pay_invoice_out_of_band)
    end

    it 'settles the sale, creates the account and opens the first renewal' do
      post '/super_admin/financial/pix_renewals/register_sale', params: { sales_quote_id: waiting.id, paid_via: 'asaas' }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['account_name']).to eq('Clínica Nova')
      expect(response.parsed_body['renewal']['due_on']).to eq((Date.current + 12.months).to_s)
      expect(waiting.reload.status).to eq('converted')
    end
  end

  it 'refuses an anonymous visitor' do
    sign_out(:super_admin)

    get '/super_admin/financial/pix_renewals/data'

    expect(response).to have_http_status(:redirect)
  end
end
