require 'rails_helper'

RSpec.describe TermsAcceptanceRequest do
  it 'accepts a valid campaign' do
    request = build(:terms_acceptance_request)

    expect(request).to be_valid
  end

  it 'requires document_date and deadline_at' do
    request = build(:terms_acceptance_request, document_date: nil, deadline_at: nil)

    expect(request).not_to be_valid
    expect(request.errors.attribute_names).to include(:document_date, :deadline_at)
  end

  # A deadline too close leaves managers no room to sign; too far away turns
  # into a request nobody remembers.
  describe 'deadline bounds' do
    it 'refuses a deadline sooner than the minimum window' do
      request = build(:terms_acceptance_request, deadline_at: 12.hours.from_now)

      expect(request).not_to be_valid
      expect(request.errors[:deadline_at]).to be_present
    end

    it 'refuses a deadline farther than the maximum window' do
      request = build(:terms_acceptance_request, deadline_at: 100.days.from_now)

      expect(request).not_to be_valid
      expect(request.errors[:deadline_at]).to be_present
    end

    it 'accepts a deadline at the boundary' do
      request = build(:terms_acceptance_request, deadline_at: (described_class::DEADLINE_MAX_DAYS - 1).days.from_now)

      expect(request).to be_valid
    end
  end

  it 'defaults kind to :update in the factory (super_admin campaigns)' do
    expect(build(:terms_acceptance_request).kind).to eq('update')
  end

  # `blocking_login_for` is what `DeviseOverrides::SessionsController` calls
  # to decide whether to refuse the login. A pinned signer is deliberately
  # let in — the modal opens for them and their signature unlocks everyone.
  describe '.blocking_login_for' do
    let(:super_admin) { create(:super_admin) }
    let(:terms_version) { create(:terms_version) }
    let(:account) { create(:account) }
    let(:manager) { create(:user, account: account) }
    let(:agent) { create(:user, account: account) }
    let(:manager_au) do
      account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) }
    end

    let(:campaign) do
      create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin, status: :expired)
    end
    let!(:acceptance) do
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: account, account_user: manager_au, kind: :update,
                                status: :pending, required: true, deadline_at: 1.day.ago)
    end

    it 'lists the account for an agent when the campaign is expired and unsigned' do
      blocking = described_class.blocking_login_for(agent)

      expect(blocking.length).to eq(1)
      expect(blocking.first[:account]).to eq(account)
      expect(blocking.first[:campaign]).to eq(campaign)
    end

    it 'lets the pinned manager in so the modal can open' do
      expect(described_class.blocking_login_for(manager)).to be_empty
    end

    it 'is empty once the required signature is signed' do
      acceptance.sign!(signer: { name: 'a', email: 'a@b.c', document: nil }, ip_address: '1.1.1.1', user_agent: 'ua')

      expect(described_class.blocking_login_for(agent)).to be_empty
    end

    it 'ignores campaigns that are still open (not yet at deadline)' do
      campaign.update!(status: :open)

      expect(described_class.blocking_login_for(agent)).to be_empty
    end
  end
end
