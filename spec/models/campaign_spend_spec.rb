require 'rails_helper'

RSpec.describe CampaignSpend do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:source_id) }
    it { is_expected.to validate_inclusion_of(:source_type).in_array(described_class::SOURCE_TYPES) }
    it { is_expected.to validate_presence_of(:period_start) }
    it { is_expected.to validate_presence_of(:period_end) }
    it { is_expected.to validate_numericality_of(:amount_cents).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }
  end

  describe 'period sanity' do
    it 'accepts period_end == period_start (daily row)' do
      row = build(:campaign_spend, period_start: Date.current, period_end: Date.current)
      expect(row).to be_valid
    end

    it 'rejects period_end before period_start' do
      row = build(:campaign_spend, period_start: Date.current, period_end: Date.current - 1)
      expect(row).to be_invalid
      expect(row.errors[:period_end].first).to include('period_start')
    end
  end

  describe 'idempotency guard' do
    # The unique index protects the daily sync — re-running the fetcher must
    # upsert the same row, not create a duplicate. The AR-level protection is
    # a raw DB constraint (RecordNotUnique) since a scoped validation would
    # miss the concurrent-write case.
    it 'rejects a duplicate (account, provider, source_id, source_type, period)' do
      first = create(:campaign_spend)

      expect do
        create(:campaign_spend,
               account: first.account, provider: first.provider,
               source_id: first.source_id, source_type: first.source_type,
               period_start: first.period_start, period_end: first.period_end)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.in_period' do
    let(:account) { create(:account) }

    it 'matches rows fully contained in the range' do
      inside = create(:campaign_spend, account: account,
                                       period_start: Date.new(2026, 9, 5),
                                       period_end: Date.new(2026, 9, 5))
      outside = create(:campaign_spend, account: account,
                                        period_start: Date.new(2026, 8, 5),
                                        period_end: Date.new(2026, 8, 5))

      results = account.campaign_spends.in_period(Date.new(2026, 9, 1), Date.new(2026, 9, 30))
      expect(results).to include(inside)
      expect(results).not_to include(outside)
    end
  end
end
