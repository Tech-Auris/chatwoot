require 'rails_helper'

RSpec.describe 'Super Admin account secretary', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before do
    create(:inbox, account: account, name: 'Recepção')
    create(:inbox, account: account, name: 'Comercial')
    sign_in(super_admin, scope: :super_admin)
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
