require 'rails_helper'

RSpec.describe 'Super Admin account integrations', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:feegow) { ErpSource.find_or_create_by!(id: 2) { |erp| erp.name = 'Feegow' } }
  let(:account) { create(:account, erp_source: feegow) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'shows the integrations on the account page with the secrets masked, and a link to add one' do
    integration = create(:account_integration, account: account, erp_source: feegow, config: { 'access_token' => 'segredo-abcd1234' })

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include("/super_admin/account_integrations/#{integration.id}/edit")
    expect(response.body).to include('••••1234')
    expect(response.body).not_to include('segredo-abcd1234')
    expect(response.body).to include("/super_admin/account_integrations/new?account_id=#{account.id}")
  end

  it 'masks the secrets in the list' do
    create(:account_integration, account: account, erp_source: feegow, config: { 'access_token' => 'segredo-abcd1234' })

    get '/super_admin/account_integrations'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('segredo-abcd1234')
  end

  it "starts the form opened from the account page on the account's ERP with its keys" do
    get '/super_admin/account_integrations/new', params: { account_id: account.id }

    expect(response.body).to include('&quot;procedimento_id&quot;: null')
  end

  it 'creates an integration from JSON and goes back to the account page' do
    post '/super_admin/account_integrations', params: {
      account_integration: { account_id: account.id, erp_source_id: feegow.id, config_json: '{"access_token": "tok", "local_id": 3}' }
    }

    expect(response).to redirect_to("/super_admin/accounts/#{account.id}")
    expect(account.account_integrations.sole.config).to eq('access_token' => 'tok', 'local_id' => 3)
  end

  it 'refuses invalid JSON' do
    integration = create(:account_integration, account: account, erp_source: feegow)

    patch "/super_admin/account_integrations/#{integration.id}", params: { account_integration: { config_json: '{oops' } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(integration.reload.config).to eq('access_token' => 'tok-1234567890', 'local_id' => '1')
  end
end
