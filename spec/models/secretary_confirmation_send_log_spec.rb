require 'rails_helper'

RSpec.describe SecretaryConfirmationSendLog do
  let(:account) { create(:account) }

  describe '.reserve' do
    it 'is true only for the call that logs the reminder' do
      expect(described_class.reserve(account: account, event_id: 1, reminder_type: '24h', calendar_id: nil)).to be(true)
      expect(described_class.reserve(account: account, event_id: '1', reminder_type: '24h', calendar_id: '')).to be(false)
      expect(described_class.reserve(account: create(:account), event_id: '1', reminder_type: '24h')).to be(true)
    end
  end
end
