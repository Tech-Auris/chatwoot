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

  # A second OpsNotif is created for agents in the same accounts — a plain
  # info notice that tells them the manager needs to sign by <deadline>.
  # Agents cannot sign, so no `subject` is attached; the modal falls through
  # to the generic "Entendi" flow.
  it 'creates an informational notification for agents of the same accounts' do
    result = perform(account_a.id => [manager_a1_au.id])

    expect(result.agent_notification).to be_persisted
    expect(result.agent_notification.audience_type).to eq('agents')
    expect(result.agent_notification.subject).to be_nil
    expect(result.agent_notification.account_ids).to eq([account_a.id])
    expect(result.agent_notification.body).to match(/gerente/i)
  end

  # The deadline is what unlocks the block; the job that flips the campaign
  # to `expired` and revokes sessions must be scheduled for exactly that
  # moment.
  it 'enqueues Terms::ExpireCampaignJob at the deadline' do
    freeze_time do
      result = perform(account_a.id => [manager_a1_au.id])

      job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j[:job] == Terms::ExpireCampaignJob }
      expect(job).to be_present
      expect(job[:args].first).to eq(result.campaign.id)
      expect(job[:at]).to be_within(1.second).of(result.campaign.deadline_at.to_f)
    end
  end
end
