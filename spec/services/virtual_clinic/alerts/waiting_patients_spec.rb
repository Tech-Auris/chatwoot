require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::WaitingPatients do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:rule) { described_class.new(account) }
  # A Tuesday at 10h in São Paulo: business hours.
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  it 'lists the patients waiting for more than 30 minutes today, the longest first' do
    old = create(:conversation, account: account, contact: create(:contact, account: account, name: 'Maria'))
    recent = create(:conversation, account: account)
    yesterday = create(:conversation, account: account)
    old.update!(waiting_since: 50.minutes.ago)
    recent.update!(waiting_since: 10.minutes.ago)
    yesterday.update!(waiting_since: 2.days.ago)

    expect(rule.payload).to eq(count: 1, minutes: 30,
                               patients: [{ name: 'Maria', conversation_id: old.display_id, waiting_minutes: 50 }])
  end

  it 'follows the limit the clinic set and stays quiet when nobody waits' do
    create(:conversation, account: account).update!(waiting_since: 50.minutes.ago)
    account.update!(settings: { 'virtual_clinic_alerts' => { 'waiting_minutes' => 60 } })

    expect(rule.payload).to be_nil
  end

  it 'only runs in business hours' do
    expect(rule).to be_due
    expect(described_class.new(account, now: Time.zone.parse('2026-11-17 02:00 UTC'))).not_to be_due
    expect(described_class.new(account, now: Time.zone.parse('2026-11-15 13:00 UTC'))).not_to be_due
  end
end
