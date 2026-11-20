require 'rails_helper'

RSpec.describe VirtualClinicSummary do
  let(:summary) { build(:virtual_clinic_summary, daily: true, weekly: true, monthly: true, hour: 8) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  it 'is due at its hour: daily every day, weekly on Mondays, monthly on the 1st' do
    expect(summary.due_periods(zone.local(2026, 12, 1, 8, 0))).to eq(%w[daily monthly])
    expect(summary.due_periods(zone.local(2026, 11, 23, 8, 0))).to eq(%w[daily weekly])
    expect(summary.due_periods(zone.local(2026, 11, 24, 8, 0))).to eq(%w[daily])
    expect(summary.due_periods(zone.local(2026, 11, 24, 9, 0))).to eq([])
  end
end
