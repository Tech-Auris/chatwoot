require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::FailedFollowUps do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  # A Tuesday at 10h in São Paulo: business hours.
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  it 'counts the follow-ups that failed today' do
    create(:follow_up, conversation: create(:conversation, account: account), delivery_status: :failed)
    create(:follow_up, conversation: create(:conversation, account: account), delivery_status: :sent)

    expect(described_class.new(account).payload).to eq(count: 1)
  end
end
