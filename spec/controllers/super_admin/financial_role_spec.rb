require 'rails_helper'

RSpec.describe 'Super admin restricted to Financeiro', type: :request do
  let(:finance_admin) { create(:super_admin, super_admin_role: SuperAdmin::FINANCIAL_ROLE) }
  let(:full_admin) { create(:super_admin) }
  let(:client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  before do
    allow(Integrations::Stripe::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_customers).and_return([])
  end

  describe 'a finance-only super admin' do
    before { sign_in(finance_admin, scope: :super_admin) }

    it 'reaches the Financeiro screens' do
      get '/super_admin/financial/invoices'

      expect(response).to have_http_status(:success)
    end

    # The whole point of the role: the finance team works on billing without
    # being handed the accounts, the users and every instance-wide setting.
    it 'is turned away from the rest of the console' do
      get '/super_admin/accounts'

      expect(response).to redirect_to('/super_admin/financial/invoices')
      expect(flash[:alert]).to include('Financeiro')
    end

    it 'is turned away from the console dashboard' do
      get '/super_admin'

      expect(response).to redirect_to('/super_admin/financial/invoices')
    end

    it 'is turned away from the instance settings' do
      get '/super_admin/settings'

      expect(response).to redirect_to('/super_admin/financial/invoices')
    end

    it 'is turned away from the users listing' do
      get '/super_admin/users'

      expect(response).to redirect_to('/super_admin/financial/invoices')
    end

    # A section added later must not be reachable just because nobody
    # remembered to add it to the list.
    it 'is turned away from a section that is not on the list' do
      get '/super_admin/reports/health_score'

      expect(response).to redirect_to('/super_admin/financial/invoices')
    end

    # Sidekiq Web is mounted outside the Administrate controllers, so the
    # console guard never runs for it — the route itself has to refuse.
    it 'cannot reach the Sidekiq queues by typing the URL' do
      get '/monitoring/sidekiq'

      expect(response).not_to have_http_status(:success)
    end

    it 'still manages its own two-factor authentication' do
      get '/super_admin/profile/mfa'

      expect(response).to have_http_status(:success)
    end

    it 'sees only the Financeiro menu in the sidebar' do
      get '/super_admin/financial/invoices'

      expect(response.body).to include('Financeiro')
      expect(response.body).not_to include('Sidekiq Dashboard')
      expect(response.body).not_to include('Platform Apps')
    end
  end

  describe 'a super admin with no role' do
    before { sign_in(full_admin, scope: :super_admin) }

    it 'keeps the whole console' do
      get '/super_admin/accounts'

      expect(response).to have_http_status(:success)
    end

    it 'still sees the rest of the sidebar' do
      get '/super_admin/accounts'

      expect(full_admin.super_admin_role).to be_nil
      expect(response.body).to include('Sidekiq Dashboard')
    end
  end

  describe 'a sales-only super admin' do
    let(:sales_admin) { create(:super_admin, super_admin_role: SuperAdmin::COMMERCIAL_ROLE) }

    before { sign_in(sales_admin, scope: :super_admin) }

    # The sales role is the same shape as the finance one: an allowlist, so a
    # console section added later is out of reach until somebody decides.
    it 'is turned away from the rest of the console' do
      get '/super_admin/accounts'

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include('Comercial')
    end

    it 'is turned away from the finance section' do
      get '/super_admin/financial/invoices'

      expect(response).to have_http_status(:redirect)
    end

    it 'still manages its own two-factor authentication' do
      get '/super_admin/profile/mfa'

      expect(response).to have_http_status(:success)
    end
  end
end
