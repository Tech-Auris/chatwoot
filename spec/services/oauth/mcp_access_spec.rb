require 'rails_helper'

RSpec.describe Oauth::McpAccess do
  let(:account) { create(:account, mcp_enabled: false) }
  let(:super_admin) { create(:super_admin) }

  def account_user_for(user, role)
    create(:account_user, account: account, user: user, role: role)
  end

  describe '.allowed?' do
    it 'lets a super admin who is an administrator in with the MCP off' do
      expect(described_class.allowed?(account_user_for(super_admin, :administrator))).to be(true)
    end

    it 'keeps requiring the MCP for a super admin who is only a manager or agent' do
      expect(described_class.allowed?(account_user_for(super_admin, :manager))).to be(false)
      expect(described_class.allowed?(account_user_for(create(:super_admin), :agent))).to be(false)
    end

    it 'keeps requiring the MCP for regular administrators and managers' do
      expect(described_class.allowed?(account_user_for(create(:user), :administrator))).to be(false)
      expect(described_class.allowed?(account_user_for(create(:user), :manager))).to be(false)

      account.update!(mcp_enabled: true)
      expect(described_class.allowed?(account_user_for(create(:user), :manager))).to be(true)
    end
  end

  describe '.accounts_for' do
    it 'lists the accounts a super admin administers, with or without the MCP' do
      account_user_for(super_admin, :administrator)
      create(:account_user, account: create(:account), user: super_admin, role: :agent)

      expect(described_class.accounts_for(super_admin)).to eq([account])
    end
  end
end
