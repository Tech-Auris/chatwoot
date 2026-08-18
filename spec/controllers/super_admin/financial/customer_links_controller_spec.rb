require 'rails_helper'

RSpec.describe 'Super Admin Financial Customer Links', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:linked_account) { create(:account, name: 'Conta Conciliada', stripe_customer_id: 'cus_linked') }
  let!(:pending_account) { create(:account, name: 'Conta Pendente') }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  def stripe_customer(id:, name: nil, email: nil)
    Struct.new(:id, :name, :email).new(id, name, email)
  end

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_customers).and_return(
      [stripe_customer(id: 'cus_linked', name: 'Conta Conciliada'), stripe_customer(id: 'cus_free', name: 'Conta Pendente')]
    )
    sign_in(super_admin, scope: :super_admin)
  end

  # Rendering the shell exercises the super admin layout, whose sidebar walks
  # every Administrate resource in the namespace — a new route without a
  # matching Dashboard class takes down every page in the console.
  describe 'GET /super_admin/financial/customer_links' do
    it 'renders the screen for a signed in super admin' do
      get '/super_admin/financial/customer_links'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('FinancialCustomerLinksIndex')
    end

    it 'redirects an unauthenticated visitor' do
      sign_out(:super_admin)

      get '/super_admin/financial/customer_links'

      expect(response).to have_http_status(:redirect)
    end

    # The screen builds every member URL by appending the account id to
    # `links_url`. A `.json` suffix on that base produces
    # ".../customer_links.json/88", which routes nowhere and surfaced as a
    # bare "Not Found" when an operator clicked Vincular.
    it 'hands the screen a base URL that still routes once an id is appended' do
      get '/super_admin/financial/customer_links'

      props = JSON.parse(Nokogiri::HTML(response.body).at_css('#app')['data-props'])
      member_path = URI.parse("#{props['links_url']}/#{pending_account.id}").path

      expect(Rails.application.routes.recognize_path(member_path, method: :patch))
        .to include(controller: 'super_admin/financial/customer_links', action: 'update')
      expect(Rails.application.routes.recognize_path("#{member_path}/customer", method: :post))
        .to include(controller: 'super_admin/financial/customer_links', action: 'customer')
    end
  end

  describe 'GET /super_admin/financial/customer_links/data' do
    it 'lists only the pending accounts by default, with suggestions' do
      get '/super_admin/financial/customer_links/data'

      names = response.parsed_body['accounts'].map { |account| account['name'] }
      expect(names).to include('Conta Pendente')
      expect(names).not_to include('Conta Conciliada')

      suggestion = response.parsed_body['accounts'].first['suggestions'].first
      expect(suggestion).to include('id' => 'cus_free', 'reason' => 'Nome parecido')
    end

    it 'lists the linked accounts with their Stripe customer on the linked scope' do
      get '/super_admin/financial/customer_links/data', params: { scope: 'linked' }

      account = response.parsed_body['accounts'].first
      expect(account['name']).to eq('Conta Conciliada')
      expect(account['stripe_customer']).to include('id' => 'cus_linked')
      expect(account['suggestions']).to be_empty
    end

    # Offering a customer that already belongs to another account would let the
    # UI break the one-to-one pairing the unique index enforces.
    it 'hides customers already linked to another account from the picker' do
      get '/super_admin/financial/customer_links/data'

      expect(response.parsed_body['customers'].map { |customer| customer['id'] }).to eq(['cus_free'])
    end

    # Stripe returns customers newest first, which makes the picker unreadable
    # once the list grows past a handful.
    it 'sorts the picker alphabetically, ignoring case and accents' do
      allow(client).to receive(:list_customers).and_return(
        [
          stripe_customer(id: 'cus_1', name: 'Vitaleskin'),
          stripe_customer(id: 'cus_2', name: 'Ângela Odonto'),
          stripe_customer(id: 'cus_3', name: 'cardiofit clinica médica ltda'),
          stripe_customer(id: 'cus_4', name: nil, email: 'zzz@exemplo.com')
        ]
      )

      get '/super_admin/financial/customer_links/data'

      expect(response.parsed_body['customers'].map { |customer| customer['id'] }).to eq(%w[cus_2 cus_3 cus_1 cus_4])
    end

    it 'filters accounts by name' do
      get '/super_admin/financial/customer_links/data', params: { search: 'Pendente' }

      expect(response.parsed_body['accounts'].map { |account| account['name'] }).to eq(['Conta Pendente'])
    end

    it 'reports the counters for both tabs' do
      get '/super_admin/financial/customer_links/data'

      expect(response.parsed_body['meta']).to include('pending_count' => 1, 'linked_count' => 1)
    end
  end

  describe 'PATCH /super_admin/financial/customer_links/:account_id' do
    it 'stores the link on both sides' do
      allow(client).to receive(:link_customer_to_account)

      patch "/super_admin/financial/customer_links/#{pending_account.id}", params: { stripe_customer_id: 'cus_free' }

      expect(response).to have_http_status(:success)
      expect(pending_account.reload.stripe_customer_id).to eq('cus_free')
      expect(client).to have_received(:link_customer_to_account).with('cus_free', pending_account.id)
    end

    it 'refuses to link a customer that already belongs to another account' do
      allow(client).to receive(:link_customer_to_account)

      patch "/super_admin/financial/customer_links/#{pending_account.id}", params: { stripe_customer_id: 'cus_linked' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('já está vinculado a outra conta')
      expect(pending_account.reload.stripe_customer_id).to be_nil
      expect(client).not_to have_received(:link_customer_to_account)
    end
  end

  describe 'DELETE /super_admin/financial/customer_links/:account_id' do
    it 'clears the link on both sides' do
      allow(client).to receive(:unlink_customer)

      delete "/super_admin/financial/customer_links/#{linked_account.id}"

      expect(response).to have_http_status(:success)
      expect(linked_account.reload.stripe_customer_id).to be_nil
      expect(client).to have_received(:unlink_customer).with('cus_linked')
    end
  end

  describe 'POST /super_admin/financial/customer_links/:account_id/customer' do
    it 'creates the Stripe customer from the account and links it' do
      admin = create(:user, account: pending_account, role: :administrator, email: 'admin@pendente.com')
      allow(client).to receive(:create_customer).and_return(stripe_customer(id: 'cus_new', name: pending_account.name))

      post "/super_admin/financial/customer_links/#{pending_account.id}/customer"

      expect(response).to have_http_status(:created)
      expect(pending_account.reload.stripe_customer_id).to eq('cus_new')
      expect(client).to have_received(:create_customer).with(
        name: 'Conta Pendente', email: admin.email, account_id: pending_account.id
      )
    end
  end

  describe 'when Stripe is not configured' do
    it 'asks the operator to save the key' do
      allow(client).to receive(:configured?).and_return(false)

      get '/super_admin/financial/customer_links/data'

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Stripe Secret Key')
    end
  end
end
