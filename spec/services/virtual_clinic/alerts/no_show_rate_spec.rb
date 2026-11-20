require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::NoShowRate do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  # A Tuesday at 10h in São Paulo: business hours.
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  it 'flags more than 15% no-shows in the last 7 days, with enough appointments' do
    create_list(:appointment, 4, account: account, status: :attended, scheduled_for: 2.days.ago)
    create(:appointment, account: account, status: :no_show, scheduled_for: 1.day.ago)
    create(:appointment, account: account, status: :no_show, scheduled_for: 20.days.ago)

    expect(described_class.new(account).payload).to eq(rate: 20.0, no_shows: 1, total: 5)
  end

  it 'runs once a day, at 9h' do
    expect(described_class.new(account, now: Time.zone.parse('2026-11-17 12:05 UTC'))).to be_due
    expect(described_class.new(account, now: Time.zone.parse('2026-11-17 12:20 UTC'))).not_to be_due
  end
end
