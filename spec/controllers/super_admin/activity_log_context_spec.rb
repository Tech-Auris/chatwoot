require 'rails_helper'

RSpec.describe 'Super Admin activity log context', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Antes') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'logs account changes as the super admin' do
    patch "/super_admin/accounts/#{account.id}", params: { account: { name: 'Depois' } }

    log = ActivityLog.find_by!(auditable_type: 'Account', auditable_id: account.id, action: 'update')
    expect(log).to have_attributes(account_id: account.id, actor_type: 'SuperAdmin', actor_id: super_admin.id, source: 'super_admin')
    expect(log.audited_changes['name']).to eq(%w[Antes Depois])
    expect(Current.audit_actor).to be_nil
  end
end
