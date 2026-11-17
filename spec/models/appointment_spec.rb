require 'rails_helper'

RSpec.describe Appointment do
  describe '.next_of' do
    let(:overdue) { described_class.new(scheduled_for: 2.days.ago) }
    let(:soon) { described_class.new(scheduled_for: 1.day.from_now) }
    let(:later) { described_class.new(scheduled_for: 5.days.from_now) }

    it 'picks the nearest upcoming appointment' do
      expect(described_class.next_of([later, overdue, soon])).to eq(soon)
    end

    it 'falls back to the latest one when none is upcoming' do
      older = described_class.new(scheduled_for: 10.days.ago)

      expect(described_class.next_of([older, overdue])).to eq(overdue)
    end

    it 'returns nil without appointments' do
      expect(described_class.next_of([])).to be_nil
    end
  end
end
