require 'rails_helper'

RSpec.describe 'Super Admin Stripe integration', type: :request do
  let(:super_admin) { create(:super_admin) }

  # The response is stubbed at the HTTP layer on purpose: the controller reads
  # nested fields off a real Stripe::Account, and a hand-rolled double would
  # hide the fact that StripeObject has no `dig`.
  def stub_account(body)
    stub_request(:get, 'https://api.stripe.com/v1/account')
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def configure_key(value)
    config = InstallationConfig.find_or_initialize_by(name: 'STRIPE_SECRET_KEY')
    config.value = value
    config.save!
    GlobalConfig.clear_cache
  end

  before do
    configure_key('sk_test_123')
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'POST /super_admin/integrations/stripe/test_connection' do
    # The payload mirrors a real GET /v1/account response, which notably has no
    # `livemode` field — the environment comes from the key instead.
    it 'reports the account name and flags a test key' do
      stub_account(id: 'acct_1', object: 'account', settings: { dashboard: { display_name: 'Auris' } })

      post '/super_admin/integrations/stripe/test_connection'

      expect(response).to redirect_to(super_admin_app_config_path(config: 'stripe'))
      expect(flash[:success]).to eq('Conexão com o Stripe OK — Auris (modo TESTE).')
    end

    it 'flags a live key so nobody mistakes the environment' do
      configure_key('sk_live_123')
      stub_account(id: 'acct_1', object: 'account', settings: { dashboard: { display_name: 'Auris' } })

      post '/super_admin/integrations/stripe/test_connection'

      expect(flash[:success]).to include('modo LIVE')
    end

    it 'falls back to the account id when the dashboard has no display name' do
      stub_account(id: 'acct_1', object: 'account')

      post '/super_admin/integrations/stripe/test_connection'

      expect(flash[:success]).to include('acct_1')
    end

    it 'surfaces an invalid credential as an alert' do
      stub_request(:get, 'https://api.stripe.com/v1/account')
        .to_return(status: 401, body: { error: { message: 'Invalid API Key provided' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post '/super_admin/integrations/stripe/test_connection'

      expect(flash[:alert]).to include('Credencial do Stripe inválida')
    end
  end
end
