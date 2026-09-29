require 'rails_helper'

RSpec.describe 'Marketing Ad Accounts API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:integration) do
    create(:marketing_integration, account: account,
                                   credentials: { 'pixel_id' => '1', 'access_token' => 'EAAG_capi', 'ads_read_token' => 'EAAG_ads' })
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}/ad_accounts" }

  def stub_lookup(external_id, status: 200, body: { name: 'Clínica Leger', currency: 'BRL' })
    stub_request(:get, %r{graph\.facebook\.com/v20\.0/act_#{external_id}\?.*access_token=EAAG_ads})
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'refuses agents' do
    get base_url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists the ad accounts, bringing in the one saved in the legacy field' do
    integration.update!(credentials: integration.credentials.merge('ad_account_id' => 'act_762067646356782'))

    get base_url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('external_id')).to eq(['762067646356782'])
  end

  it 'adds an ad account the token can read, with its name from Meta' do
    stub_lookup('762067646356782')

    post base_url, params: { external_id: 'act_762067646356782' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('external_id' => '762067646356782', 'name' => 'Clínica Leger', 'enabled' => true)
  end

  it 'refuses an ad account the token cannot read, with the Meta message' do
    stub_lookup('111', status: 403, body: { error: { message: 'Ad account owner has NOT grant ads_read permission' } })

    post base_url, params: { external_id: '111' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('ads_read')
    expect(integration.ad_accounts).to be_empty
  end

  it 'turns an ad account off and removes it' do
    ad_account = integration.ad_accounts.create!(account: account, external_id: '222')

    patch "#{base_url}/#{ad_account.id}", params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(ad_account.reload.enabled).to be(false)

    delete "#{base_url}/#{ad_account.id}", headers: admin.create_new_auth_token, as: :json
    expect(MarketingAdAccount.exists?(ad_account.id)).to be(false)
  end

  it 'queues a sync of the last 30 days' do
    expect do
      post "#{base_url}/sync", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(Marketing::MetaAdAccountsSyncJob).with(account.id)
    expect(response).to have_http_status(:accepted)
  end
end
