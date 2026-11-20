require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::ConversionDrop do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:rule) { described_class.new(account) }
  # A Tuesday at 10h in São Paulo: business hours.
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  it 'flags a week 20% below the 4 weeks before' do
    weeks = [{ leads: 10, appointments: 2 }] + Array.new(4, { leads: 10, appointments: 4 })
    allow(rule).to receive(:numbers).and_return(*weeks)

    expect(rule.payload).to eq(rate: 20.0, average: 40.0)
  end

  it 'stays quiet on a normal or a too quiet week' do
    allow(rule).to receive(:numbers).and_return(*([{ leads: 10, appointments: 4 }] * 5))
    expect(rule.payload).to be_nil

    allow(rule).to receive(:numbers).and_return({ leads: 3, appointments: 0 })
    expect(rule.payload).to be_nil
  end
end
