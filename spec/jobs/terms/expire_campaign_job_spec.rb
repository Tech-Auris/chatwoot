require 'rails_helper'

RSpec.describe Terms::ExpireCampaignJob do
  let(:super_admin) { create(:super_admin) }
  let(:terms_version) { create(:terms_version) }
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:manager_au) { account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) } }

  let(:campaign) { create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin) }
  let!(:acceptance) do
    create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                              account: account, account_user: manager_au, kind: :update,
                              status: :pending, required: true, deadline_at: campaign.deadline_at)
  end

  before do
    # Seed real sessions so we can prove the job actually cut them.
    manager.tokens = { 'client-a' => { 'token' => 't1', 'expiry' => 1.day.from_now.to_i } }
    manager.save!
    manager.user_sessions.create!(client_id: 'client-a', ip_address: '1.1.1.1', user_agent: 'ua')

    agent.tokens = { 'client-b' => { 'token' => 't2', 'expiry' => 1.day.from_now.to_i } }
    agent.save!
    agent.user_sessions.create!(client_id: 'client-b', ip_address: '2.2.2.2', user_agent: 'ua')
  end

  it 'flips the campaign to expired' do
    described_class.perform_now(campaign.id)

    expect(campaign.reload.status).to eq('expired')
  end

  it 'wipes tokens + destroys sessions of every user in the pending accounts (manager and agent both)' do
    described_class.perform_now(campaign.id)

    expect(manager.reload.tokens).to eq({})
    expect(agent.reload.tokens).to eq({})
    expect(manager.user_sessions).to be_empty
    expect(agent.user_sessions).to be_empty
  end

  # The manager can re-login right away (the modal opens and lets them sign);
  # the point of the revoke is that the current session is severed so the
  # decision is auditable — everybody starts from scratch.
  it 'leaves accounts that have no pending required signature alone' do
    unrelated_account = create(:account)
    other_user = create(:user, account: unrelated_account)
    other_user.tokens = { 'client-c' => { 'token' => 't3', 'expiry' => 1.day.from_now.to_i } }
    other_user.save!

    described_class.perform_now(campaign.id)

    expect(other_user.reload.tokens.dig('client-c', 'token')).to eq('t3')
  end

  # Prevents double-revoking if the job somehow runs twice (Sidekiq retry after
  # a partial failure), or if a super_admin closed the campaign early.
  it 'is a no-op when the campaign is not open anymore' do
    campaign.update!(status: :closed)

    described_class.perform_now(campaign.id)

    expect(manager.reload.tokens).not_to eq({})
    expect(campaign.reload.status).to eq('closed')
  end

  # A signed campaign at the deadline moment still expires (the row is not
  # `open` any longer via status but... actually still `open`, since acceptances
  # signed don't flip the campaign). The point being: we only revoke for
  # accounts that HAVE a pending required signature. An account whose manager
  # signed keeps its sessions.
  it 'does not revoke users of accounts that already signed' do
    acceptance.sign!(signer: { name: 'a', email: 'a@b.c', document: nil }, ip_address: '1.1.1.1', user_agent: 'ua')

    described_class.perform_now(campaign.id)

    expect(manager.reload.tokens).not_to eq({})
    expect(agent.reload.tokens).not_to eq({})
    expect(campaign.reload.status).to eq('expired')
  end
end
