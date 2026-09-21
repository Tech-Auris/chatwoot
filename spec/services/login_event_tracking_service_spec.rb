require 'rails_helper'

RSpec.describe LoginEventTrackingService do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:user) { create(:user) }
  let(:request) do
    instance_double(
      ActionDispatch::Request,
      remote_ip: '203.0.113.10',
      user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1 Safari/605.1'
    )
  end

  before do
    create(:account_user, account: account_a, user: user, role: :administrator)
    create(:account_user, account: account_b, user: user, role: :agent)
    allow(LoginEventIpLookupJob).to receive(:perform_later)
  end

  describe '#perform' do
    it 'creates one event per account membership with the current role snapshot' do
      expect { described_class.new(user: user, request: request).perform }
        .to change(LoginEvent, :count).by(2)

      events = LoginEvent.where(user: user).order(:account_id)
      expect(events.pluck(:account_id)).to contain_exactly(account_a.id, account_b.id)
      expect(events.find_by(account: account_a).role).to eq('administrator')
      expect(events.find_by(account: account_b).role).to eq('agent')
    end

    it 'captures IP and user agent metadata on every row' do
      described_class.new(user: user, request: request).perform

      event = LoginEvent.last
      expect(event.ip_address).to eq('203.0.113.10')
      expect(event.user_agent).to include('Mozilla/5.0')
      expect(event.browser_name).to eq('Safari')
    end

    it 'enqueues the IP lookup job so city/country are back-filled asynchronously' do
      described_class.new(user: user, request: request).perform

      expect(LoginEventIpLookupJob).to have_received(:perform_later).twice
    end

    it 'still records a single row when the user has no account membership' do
      lonely = create(:user)

      expect { described_class.new(user: lonely, request: request).perform }
        .to change(LoginEvent, :count).by(1)

      event = LoginEvent.where(user: lonely).sole
      expect(event.account_id).to be_nil
      expect(event.role).to be_nil
    end
  end
end
