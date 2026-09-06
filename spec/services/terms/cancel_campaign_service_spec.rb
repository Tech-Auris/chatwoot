require 'rails_helper'

RSpec.describe Terms::CancelCampaignService do
  let(:super_admin) { create(:super_admin) }
  let(:terms_version) { create(:terms_version) }
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account) }
  let(:manager_au) { account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) } }
  let(:campaign) { create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin) }
  let!(:acceptance) do
    create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                              account: account, account_user: manager_au, kind: :update,
                              status: :pending, required: true, deadline_at: campaign.deadline_at)
  end
  let!(:notification) do
    OperationsNotification.create!(
      title: 'Novos termos', body: 'Assine', severity: :emergency,
      scope_type: :all_accounts, audience_type: :managers, trigger_kind: :on_login,
      published_at: 1.minute.ago, created_by: super_admin, subject: campaign
    )
  end
  let!(:agent_notice) do
    OperationsNotification.create!(
      title: 'Novos termos', body: 'aviso pros agentes', severity: :info,
      scope_type: :accounts, account_ids: [account.id], audience_type: :agents,
      trigger_kind: :on_login, published_at: 1.minute.ago, created_by: super_admin,
      created_at: campaign.created_at + 1.second
    )
  end

  it 'closes the campaign' do
    described_class.new(campaign).perform

    expect(campaign.reload.status).to eq('closed')
  end

  # Cancelling a signature is what makes the acceptance no longer count as
  # "still owed" — the audit trail is preserved, the row is not deleted.
  it 'cancels every acceptance still pending' do
    described_class.new(campaign).perform

    expect(acceptance.reload.status).to eq('cancelled')
  end

  it 'soft-deletes the OpsNotifs the campaign produced (manager subject + agent notice)' do
    described_class.new(campaign).perform

    expect(notification.reload.deleted_at).to be_present
    expect(agent_notice.reload.deleted_at).to be_present
  end

  it 'leaves unrelated notifications alone' do
    unrelated = OperationsNotification.create!(
      title: 'Outro aviso', body: 'x', severity: :info,
      scope_type: :all_accounts, audience_type: :all_users, trigger_kind: :on_login,
      published_at: 1.day.ago, created_by: super_admin
    )

    described_class.new(campaign).perform

    expect(unrelated.reload.deleted_at).to be_nil
  end

  it 'no-ops sidekiq cleanup even when no job is scheduled' do
    expect { described_class.new(campaign).perform }.not_to raise_error
  end

  # A signed acceptance already reflects the audit trail and must not be
  # rewritten as cancelled — the signature stands.
  it 'leaves signed acceptances alone' do
    acceptance.sign!(signer: { name: 'a', email: 'a@b.c', document: nil }, ip_address: '1.1.1.1', user_agent: 'ua')

    described_class.new(campaign).perform

    expect(acceptance.reload.status).to eq('signed')
  end
end
