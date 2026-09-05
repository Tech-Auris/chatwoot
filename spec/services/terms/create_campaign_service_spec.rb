require 'rails_helper'

RSpec.describe Terms::CreateCampaignService do
  let(:super_admin) { create(:super_admin) }
  let(:terms_version) { create(:terms_version) }
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:manager_a1) { create(:user, account: account_a) }
  let(:manager_a2) { create(:user, account: account_a) }
  let(:manager_b1) { create(:user, account: account_b) }
  let(:manager_a1_au) { account_a.account_users.find_by(user: manager_a1).tap { |au| au.update!(role: :manager) } }
  let(:manager_a2_au) { account_a.account_users.find_by(user: manager_a2).tap { |au| au.update!(role: :manager) } }
  let(:manager_b1_au) { account_b.account_users.find_by(user: manager_b1).tap { |au| au.update!(role: :manager) } }

  def perform(required)
    described_class.new(
      super_admin: super_admin,
      terms_version: terms_version,
      document_date: Date.new(2026, 9, 3),
      deadline_at: 7.days.from_now,
      required_signers_by_account: required
    ).perform
  end

  it 'creates the campaign, one acceptance per required signer, and the notification' do
    result = perform(account_a.id => [manager_a1_au.id, manager_a2_au.id], account_b.id => [manager_b1_au.id])

    expect(result.campaign).to be_persisted
    expect(result.acceptance_count).to eq(3)
    expect(TermsAcceptance.where(terms_acceptance_request: result.campaign).pluck(:account_user_id))
      .to contain_exactly(manager_a1_au.id, manager_a2_au.id, manager_b1_au.id)
    expect(result.notification.subject).to eq(result.campaign)
    expect(result.notification.audience_type).to eq('managers')
  end

  # Every acceptance produced by a campaign is a required signer — the flag
  # is what the report leans on to answer "is this account done?".
  it 'marks each generated acceptance as required' do
    result = perform(account_a.id => [manager_a1_au.id])

    expect(result.campaign.terms_acceptances.pluck(:required)).to all(be true)
  end

  # A campaign notification scoped to the accounts on the roster keeps the
  # modal from opening on managers whose account was left out of the wizard.
  it 'scopes the notification to the accounts on the roster' do
    result = perform(account_a.id => [manager_a1_au.id])

    expect(result.notification.scope_type).to eq('accounts')
    expect(result.notification.account_ids).to eq([account_a.id])
  end

  # The three writes go together — nothing partial should escape the wizard.
  it 'rolls back everything if the notification fails to persist' do
    allow(OperationsNotification).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(OperationsNotification.new))

    expect do
      perform(account_a.id => [manager_a1_au.id])
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(TermsAcceptanceRequest.count).to eq(0)
    expect(TermsAcceptance.where(kind: :update).count).to eq(0)
  end
end
