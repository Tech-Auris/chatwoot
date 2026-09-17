# A single day of ad spend on a single ad (Meta) or campaign (Google) as
# reported by the provider's API. See CreateCampaignSpends migration for the
# broader design; this file holds the model surface the report and the
# fetchers use.
#
# The unique index on (account_id, provider, source_id, source_type,
# period_start, period_end) is the idempotency key — the sync job upserts by
# it every day so re-runs are cheap and safe.
# == Schema Information
#
# Table name: campaign_spends
#
#  id                :bigint           not null, primary key
#  amount_cents      :integer          default(0), not null
#  currency          :string           not null
#  external_metadata :jsonb            not null
#  last_synced_at    :datetime         not null
#  period_end        :date             not null
#  period_start      :date             not null
#  provider          :integer          not null
#  source_type       :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  source_id         :string           not null
#
# Indexes
#
#  idx_on_account_id_period_start_period_end_7b6f75a74c  (account_id,period_start,period_end)
#  index_campaign_spends_unique                          (account_id,provider,source_id,source_type,period_start,period_end) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CampaignSpend < ApplicationRecord
  PROVIDERS = { meta: 0, google_ads: 1 }.freeze
  SOURCE_TYPES = %w[meta_ad meta_campaign google_ads_campaign].freeze

  enum provider: PROVIDERS

  belongs_to :account

  validates :source_id, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :period_start, :period_end, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validate :period_end_after_start

  scope :in_period, ->(from, to) { where('period_start >= ? AND period_end <= ?', from, to) }

  # Money helper so callers don't spread cents math around.
  def amount
    amount_cents / 100.0
  end

  private

  def period_end_after_start
    return if period_start.blank? || period_end.blank?

    errors.add(:period_end, 'must be on or after period_start') if period_end < period_start
  end
end
