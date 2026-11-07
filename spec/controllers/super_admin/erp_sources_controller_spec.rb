require 'rails_helper'

RSpec.describe 'Super Admin ERP sources dashboard', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:erp_source) { create(:erp_source, id: 2, name: 'Feegow') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'lists the ERPs' do
    get '/super_admin/erp_sources'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Feegow')
  end

  it 'creates an ERP with the id it has in Supabase' do
    post '/super_admin/erp_sources', params: { erp_source: { id: 17, name: 'Novo ERP', active: true } }

    expect(ErpSource.find(17).name).to eq('Novo ERP')
  end

  it 'renames and deactivates an ERP without touching its id' do
    patch "/super_admin/erp_sources/#{erp_source.id}", params: { erp_source: { id: 99, name: 'Feegow v2', active: false } }

    expect(erp_source.reload).to have_attributes(id: 2, name: 'Feegow v2', active: false)
  end

  it 'keeps an ERP an account uses' do
    create(:account, erp_source: erp_source)

    delete "/super_admin/erp_sources/#{erp_source.id}"

    expect(ErpSource.exists?(erp_source.id)).to be(true)
  end

  it 'sets the ERP of an account' do
    account = create(:account)

    patch "/super_admin/accounts/#{account.id}", params: { account: { name: account.name, erp_source_id: erp_source.id } }

    expect(account.reload.erp_source).to eq(erp_source)
  end

  it 'shows the ERP on the account page' do
    account = create(:account, erp_source: erp_source)

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include('Feegow')
  end

  it "offers the active ERPs on the account form, plus the account's own when it was retired" do
    retired = create(:erp_source, id: 9, name: 'Prodoctor', active: false)
    create(:erp_source, id: 10, name: 'Amplimed antigo', active: false)
    account = create(:account, erp_source: retired)

    get "/super_admin/accounts/#{account.id}/edit"

    expect(response.body).to include('Feegow', 'Prodoctor')
    expect(response.body).not_to include('Amplimed antigo')
  end
end
