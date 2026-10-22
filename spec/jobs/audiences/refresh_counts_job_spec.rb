require 'rails_helper'

RSpec.describe Audiences::RefreshCountsJob do
  it 'recounts the dynamic audiences as their conversations change' do
    account = create(:account)
    audience = create(:audience, account: account)
    create(:conversation, account: account)

    described_class.perform_now

    expect(audience.reload).to have_attributes(contacts_count: 1)
    expect(audience.counted_at).to be_present
  end
end
