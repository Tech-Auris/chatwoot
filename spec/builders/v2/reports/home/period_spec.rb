require 'rails_helper'

RSpec.describe V2::Reports::Home::Period do
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { zone.parse('2026-11-11 15:00') }

  it 'draws the 5 days before a single day' do
    period = described_class.new(since: now.beginning_of_day, until_time: now)

    expect(period.granularity).to eq(:day)
    expect(period.buckets.map { |bucket| bucket.first.day }).to eq([7, 8, 9, 10, 11])
    expect(period.previous).to eq((now.beginning_of_day - 15.hours)...now.beginning_of_day)
  end

  it 'draws a point per day for 7 days and per week for a month' do
    week = described_class.new(since: now.beginning_of_day - 6.days, until_time: now)
    month = described_class.new(since: now.beginning_of_day - 29.days, until_time: now)

    expect(week.buckets.size).to eq(7)
    expect(month.granularity).to eq(:week)
    expect(month.buckets.size).to eq(5)
    expect(month.buckets.last.last).to eq(now)
  end

  it 'draws a point per month beyond 90 days' do
    period = described_class.new(since: now - 120.days, until_time: now)

    expect(period.granularity).to eq(:month)
    expect(period.buckets.first.first).to eq(now - 120.days)
  end
end
