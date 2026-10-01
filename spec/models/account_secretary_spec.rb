require 'rails_helper'

RSpec.describe AccountSecretary do
  let(:account) { create(:account) }
  let(:version) { create(:secretary_version) }
  let(:inbox) { create(:inbox, account: account) }
  let(:simulator_inbox) do
    account.ensure_simulator_inbox!
    account.reload.simulator_inbox
  end

  describe '#version_for' do
    let(:secretary) { create(:account_secretary, account: account, secretary_version: version) }

    it 'returns the account version for an enabled inbox' do
      inbox.update!(secretary_enabled: true)

      expect(secretary.version_for(inbox)).to eq(version)
    end

    it 'returns nil for an inbox the secretary does not answer on' do
      expect(secretary.version_for(inbox)).to be_nil
    end

    it 'falls back to the account version on the Simulador inbox' do
      expect(secretary.version_for(simulator_inbox)).to eq(version)
    end

    it 'uses the testing version on the Simulador inbox, even without an account version' do
      testing = create(:secretary_version, status: :testing)
      secretary.update!(secretary_version: nil, simulator_version: testing)

      expect(secretary.version_for(simulator_inbox)).to eq(testing)
    end
  end

  describe 'validations' do
    it 'does not let the account pick a testing version' do
      secretary = described_class.new(account: account, secretary_version: create(:secretary_version, status: :testing))

      expect(secretary).not_to be_valid
    end

    it 'does not let the Simulador pick a retired version' do
      secretary = described_class.new(account: account, simulator_version: create(:secretary_version, status: :retired))

      expect(secretary).not_to be_valid
    end

    it 'keeps working on a version retired after it was picked' do
      secretary = create(:account_secretary, account: account, secretary_version: version)
      version.update!(status: :retired)

      expect(secretary.reload).to be_valid
    end
  end
end
