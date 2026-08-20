require 'rails_helper'

RSpec.describe 'Platform Financial Accounts API', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }
  let!(:billed) { create(:account, name: 'Cobra tokens', stripe_customer_id: 'cus_1') }
  let!(:opted_out) { create(:account, name: 'Não cobra', stripe_customer_id: 'cus_2', token_billing_enabled: false) }
  let!(:unlinked) { create(:account, name: 'Sem cliente') }

  it 'rejects a request without a platform token' do
    get '/platform/api/v1/financial/accounts'

    expect(response).to have_http_status(:unauthorized)
  end

  it 'reports the token billing flag of every account' do
    get '/platform/api/v1/financial/accounts', headers: headers

    by_id = response.parsed_body['accounts'].index_by { |row| row['id'] }
    expect(by_id[billed.id]).to include('token_billing_enabled' => true, 'stripe_customer_id' => 'cus_1', 'billable' => true)
    expect(by_id[opted_out.id]).to include('token_billing_enabled' => false, 'billable' => false)
  end

  # Billing needs both halves: the account has to be charged AND have somewhere
  # to be charged.
  it 'reports an account with no Stripe customer as not billable' do
    get '/platform/api/v1/financial/accounts', headers: headers

    row = response.parsed_body['accounts'].find { |account| account['id'] == unlinked.id }
    expect(row).to include('token_billing_enabled' => true, 'stripe_customer_id' => nil, 'billable' => false)
  end

  # `false` is a real filter — a blank check that treats it as "no filter" would
  # silently answer with every account instead.
  it 'filters by the accounts opted out of token billing' do
    get '/platform/api/v1/financial/accounts', params: { token_billing_enabled: false }, headers: headers

    expect(response.parsed_body['accounts'].pluck('id')).to eq([opted_out.id])
  end

  it 'filters by the accounts that are charged' do
    get '/platform/api/v1/financial/accounts', params: { token_billing_enabled: true }, headers: headers

    expect(response.parsed_body['accounts'].pluck('id')).to contain_exactly(billed.id, unlinked.id)
  end

  it 'can leave out the accounts with no Stripe customer' do
    get '/platform/api/v1/financial/accounts', params: { linked_only: true }, headers: headers

    expect(response.parsed_body['accounts'].pluck('id')).to contain_exactly(billed.id, opted_out.id)
  end

  it 'pages the listing' do
    get '/platform/api/v1/financial/accounts', params: { per_page: 2, page: 2 }, headers: headers

    expect(response.parsed_body['accounts'].length).to eq(1)
    expect(response.parsed_body['meta']).to include('current_page' => 2, 'total_count' => 3)
  end
end
