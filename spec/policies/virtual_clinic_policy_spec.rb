require 'rails_helper'

RSpec.describe VirtualClinicPolicy, type: :policy do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :manager) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def policy_for(user)
    described_class.new({ user: user, account: account, account_user: account.account_users.find_by(user: user) }, :virtual_clinic)
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account)
  end

  it 'opens the page to every role when the account is released' do
    expect([admin, manager, agent].map { |user| policy_for(user).show? }).to all(be(true))
  end

  it 'closes the page to everyone when the account is not released' do
    account.update!(virtual_clinic_enabled: false)

    expect(policy_for(admin).show?).to be(false)
    expect(policy_for(admin).ai_team?).to be(false)
  end

  it 'gives the AI team to administrators and managers only' do
    expect(policy_for(admin).ai_team?).to be(true)
    expect(policy_for(manager).ai_team?).to be(true)
    expect(policy_for(agent).ai_team_visible?).to be(false)
    expect(policy_for(agent).ai_team?).to be(false)
  end

  it 'reports the AI assistant as missing before the OpenAI key' do
    account.update!(mcp_enabled: false)

    expect(policy_for(admin).ai_team?).to be(false)
    expect(policy_for(admin).missing_requirement).to eq('mcp')
  end

  it 'requires the clinic own OpenAI key' do
    account.hooks.where(app_id: 'openai').delete_all

    expect(policy_for(admin).ai_team?).to be(false)
    expect(policy_for(admin).missing_requirement).to eq('openai_key')
  end
end
