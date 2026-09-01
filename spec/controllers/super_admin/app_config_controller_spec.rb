require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { create(:installation_config, { name: 'FB_APP_ID', value: 'TESTVALUE' }) }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end
    end
  end

  # The Auris-only sections live in their own mapping so a sync with upstream
  # does not conflict on every entry.
  describe 'the AsaaS section' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows the key of the account money comes in through' do
      create(:installation_config, name: 'ASAAS_API_KEY', value: '$aact_test_key')

      get '/super_admin/app_config?config=asaas'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('$aact_test_key')
    end

    it 'saves the key' do
      post '/super_admin/app_config?config=asaas', params: { app_config: { ASAAS_API_KEY: '$aact_nova' } }

      expect(GlobalConfig.get('ASAAS_API_KEY')['ASAAS_API_KEY']).to eq('$aact_nova')
    end

    # Every section is an allowlist: a key that is not part of it must not be
    # writable through it.
    it 'refuses to write another section key through it' do
      post '/super_admin/app_config?config=asaas', params: { app_config: { STRIPE_SECRET_KEY: 'sk_live_x' } }

      expect(GlobalConfig.get('STRIPE_SECRET_KEY')['STRIPE_SECRET_KEY']).to be_blank
    end

    it 'is listed in the settings menu' do
      get '/super_admin/settings'

      expect(response.body).to include('AsaaS')
    end
  end

  # The proposal a prospect opens is neither the console nor the product, and
  # what it carries was living in the database with no screen to reach it.
  describe 'the Comercial section' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'holds the logo and the pix code of the proposal' do
      create(:installation_config, name: 'SALES_PIX_PAYLOAD', value: '00020101021126360014br.gov.bcb.pix')
      create(:installation_config, name: 'SALES_PROPOSAL_LOGO', value: '/brand-assets/auris_sales_logo.png')

      get '/super_admin/app_config?config=commercial'

      expect(response.body).to include('00020101021126360014br.gov.bcb.pix')
      expect(response.body).to include('/brand-assets/auris_sales_logo.png')
    end

    it 'saves the logo of the proposal' do
      post '/super_admin/app_config?config=commercial',
           params: { app_config: { SALES_PROPOSAL_LOGO: '/brand-assets/auris_sales_logo.png' } }

      expect(GlobalConfig.get('SALES_PROPOSAL_LOGO')['SALES_PROPOSAL_LOGO']).to eq('/brand-assets/auris_sales_logo.png')
    end

    it 'is listed in the settings menu' do
      get '/super_admin/settings'

      expect(response.body).to include('Comercial')
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end
    end
  end
end
