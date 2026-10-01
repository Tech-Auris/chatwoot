require 'rails_helper'

RSpec.describe 'Super Admin account secretary', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:reception) { create(:inbox, account: account, name: 'Recepção') }
  let!(:sales) { create(:inbox, account: account, name: 'Comercial') }
  let(:version) { create(:secretary_version, name: 'v3.2') }
  let(:testing) { create(:secretary_version, name: 'v3.4', status: :testing) }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'PATCH /super_admin/accounts/:account_id/secretary' do
    it 'saves the version, the Simulador version and the inboxes it answers on' do
      patch "/super_admin/accounts/#{account.id}/secretary",
            params: { secretary_version_id: version.id, simulator_version_id: testing.id, inbox_ids: [reception.id] }, as: :json

      expect(response).to have_http_status(:ok)
      secretary = account.reload.account_secretary
      expect(secretary).to have_attributes(secretary_version: version, simulator_version: testing)
      expect(secretary.secret).to be_present
      expect(reception.reload.secretary_enabled).to be(true)
      expect(sales.reload.secretary_enabled).to be(false)
    end

    it 'turns the inboxes off when they are removed' do
      reception.update!(secretary_enabled: true)

      patch "/super_admin/accounts/#{account.id}/secretary", params: { secretary_version_id: version.id, inbox_ids: [] }, as: :json

      expect(reception.reload.secretary_enabled).to be(false)
    end

    it 'refuses a testing version for the account' do
      patch "/super_admin/accounts/#{account.id}/secretary", params: { secretary_version_id: testing.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /super_admin/accounts/:account_id/secretary/regenerate_secret' do
    it 'replaces the signing secret' do
      secretary = create(:account_secretary, account: account)
      old_secret = secretary.secret

      post "/super_admin/accounts/#{account.id}/secretary/regenerate_secret", as: :json

      expect(response.parsed_body['secret']).to be_present
      expect(secretary.reload.secret).not_to eq(old_secret)
    end
  end

  describe 'GET /super_admin/accounts/:account_id/secretary' do
    it 'lists the inboxes without the Simulador' do
      account.ensure_simulator_inbox!

      get "/super_admin/accounts/#{account.id}/secretary", as: :json

      names = response.parsed_body['inboxes'].pluck('name')
      expect(names).to contain_exactly('Recepção', 'Comercial')
      expect(response.parsed_body['simulator_inbox']).to be_present
    end
  end
end
