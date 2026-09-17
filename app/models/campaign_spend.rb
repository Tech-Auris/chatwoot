# A single day of ad spend on a single ad (Meta) or campaign (Google) as
# reported by the provider's API. See CreateCampaignSpends migration for the
# broader design; this file holds the model surface the report and the
# fetchers use.
#
# The unique index on (account_id, provider, source_id, source_type,
# period_start, period_end) is the idempotency key — the sync job upserts by
# it every day so re-runs are cheap and safe.
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
