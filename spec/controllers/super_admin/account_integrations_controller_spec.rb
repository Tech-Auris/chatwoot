require 'rails_helper'

RSpec.describe 'Super Admin account integrations', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:feegow) { create(:erp_source, :with_fields, id: 2, name: 'Feegow') }
  let(:account) { create(:account, erp_source: feegow) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'shows the integrations on the account page with the secrets masked, and a way to configure one' do
    integration = create(:account_integration, account: account, erp_source: feegow, config: { 'access_token' => 'segredo-abcd1234' })

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include("/super_admin/account_integrations/#{integration.id}/edit")
    expect(response.body).to include('seg••••1234')
    expect(response.body).not_to include('segredo-abcd1234')
    expect(response.body).to include("/super_admin/account_integrations/configure?account_id=#{account.id}&amp;erp_source_id=#{feegow.id}")
  end

  it 'masks the secrets in the list, which has no New button' do
    create(:account_integration, account: account, erp_source: feegow, config: { 'access_token' => 'segredo-abcd1234' })

    get '/super_admin/account_integrations'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('segredo-abcd1234')
    expect(response.body).not_to include('/super_admin/account_integrations/new')
  end

  describe 'configure' do
    it 'opens the existing integration of the account with the ERP' do
      integration = create(:account_integration, account: account, erp_source: feegow)

      get '/super_admin/account_integrations/configure', params: { account_id: account.id, erp_source_id: feegow.id }

      expect(response).to redirect_to("/super_admin/account_integrations/#{integration.id}/edit")
    end

    it 'opens a new one, with one input per field of the ERP, when there is none' do
      get '/super_admin/account_integrations/configure', params: { account_id: account.id, erp_source_id: feegow.id }
      follow_redirect!

      expect(response.body).to include('name="account_integration[config_values][access_token]"')
      expect(response.body).to include('type="password"')
      expect(response.body).to include('type="number"')
      expect(response.body).to include('name="account_integration[config_values][token_overrides]"')
    end
  end

  it 'creates an integration from the field inputs and goes back to the account page' do
    post '/super_admin/account_integrations', params: {
      account_integration: { account_id: account.id, erp_source_id: feegow.id,
                             config_values: { access_token: 'tok', local_id: '3', token_overrides: '' } }
    }

    expect(response).to redirect_to("/super_admin/accounts/#{account.id}")
    expect(account.account_integrations.sole.config).to eq('access_token' => 'tok', 'local_id' => 3, 'token_overrides' => nil)
  end

  it 'keeps the saved secret when it is left blank and refuses an invalid number' do
    integration = create(:account_integration, account: account, erp_source: feegow)

    patch "/super_admin/account_integrations/#{integration.id}",
          params: { account_integration: { config_values: { access_token: '', local_id: 'x' } } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/super_admin/account_integrations/#{integration.id}",
          params: { account_integration: { config_values: { access_token: '', local_id: '9' } } }
    expect(integration.reload.config).to eq('access_token' => 'tok-1234567890', 'local_id' => 9)
  end

  describe 'account ERP' do
    it 'can be cleared' do
      patch "/super_admin/accounts/#{account.id}", params: { account: { name: account.name, erp_source_id: '' } }

      expect(account.reload.erp_source_id).to be_nil
    end

    it 'saves and opens the integration with "Save and configure the integration"' do
      other = create(:account)

      patch "/super_admin/accounts/#{other.id}", params: { account: { name: other.name, erp_source_id: feegow.id }, configure_integration: '1' }

      expect(response).to redirect_to("/super_admin/account_integrations/configure?account_id=#{other.id}&erp_source_id=#{feegow.id}")
      expect(other.reload.erp_source_id).to eq(feegow.id)
    end
  end

  it 'edits the fields of an ERP as rows' do
    patch "/super_admin/erp_sources/#{feegow.id}", params: {
      erp_source: { name: 'Feegow', fields: { '0' => { key: 'access_token', label: 'Token', type: 'text', secret: '1' }, '1' => { key: '' } } }
    }

    expect(feegow.reload.fields).to eq([{ 'key' => 'access_token', 'label' => 'Token', 'type' => 'text', 'secret' => true }])
  end
end
