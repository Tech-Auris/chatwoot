require 'rails_helper'

RSpec.describe AiOffSchedulable do
  let(:inbox) { create(:inbox, ai_schedule_enabled: true, timezone: 'America/Sao_Paulo') }

  before do
    inbox.ai_off_hours.create!(day_of_week: 2, from_minutes: 8 * 60, to_minutes: 12 * 60)
    inbox.ai_off_hours.create!(day_of_week: 2, from_minutes: 13 * 60, to_minutes: 18 * 60)
  end

  # 2026-10-27 is a Tuesday.
  def at(time)
    Time.find_zone('America/Sao_Paulo').parse("2026-10-27 #{time}")
  end

  it 'is off inside any of the ranges of the day, in the inbox timezone' do
    expect(inbox.ai_off_now?(at('09:00'))).to be(true)
    expect(inbox.ai_off_now?(at('13:00'))).to be(true)
    expect(inbox.ai_off_now?(at('11:59').utc)).to be(true)
  end

  it 'is on between the ranges, at the end of a range and on days without ranges' do
    expect(inbox.ai_off_now?(at('12:30'))).to be(false)
    expect(inbox.ai_off_now?(at('18:00'))).to be(false)
    expect(inbox.ai_off_now?(at('09:00') + 1.day)).to be(false)
  end

  it 'uses the inbox timezone even without business hours or with another account timezone' do
    inbox.account.update!(reporting_timezone: 'UTC')

    expect(inbox.ai_off_now?(at('09:00'))).to be(true)
    expect(inbox.ai_off_now?(Time.utc(2026, 10, 27, 9))).to be(false)
  end

  it 'is on when the schedule is turned off' do
    inbox.update!(ai_schedule_enabled: false)

    expect(inbox.ai_off_now?(at('09:00'))).to be(false)
  end

  it 'refuses a range that ends before it starts' do
    hour = inbox.ai_off_hours.build(day_of_week: 1, from_minutes: 600, to_minutes: 540)

    expect(hour).not_to be_valid
  end
end
