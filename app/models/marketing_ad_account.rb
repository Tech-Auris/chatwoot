# A Meta ad account whose daily spend the integration pulls into
# `campaign_spends`. Added one by one from Marketing → Pixel e Dados; the
# last sync outcome is kept on the row so the grid can flag an account that
# lost access without anyone reading the logs.
class MarketingAdAccount < ApplicationRecord
  SYNC_STATUSES = %w[ok error].freeze

  belongs_to :account
  belongs_to :marketing_integration

  before_validation :normalize_external_id

  validates :external_id, format: { with: /\A\d+\z/, message: ->(*) { I18n.t('errors.marketing_ad_account.invalid_id') } },
                          uniqueness: { scope: :marketing_integration_id,
                                        message: ->(*) { I18n.t('errors.marketing_ad_account.already_added') } }
  validates :last_sync_status, inclusion: { in: SYNC_STATUSES }, allow_nil: true

  scope :enabled, -> { where(enabled: true) }

  def record_sync!(rows_synced:)
    update!(last_synced_at: Time.current, last_sync_status: 'ok', last_sync_error: nil, last_rows_synced: rows_synced)
  end

  def record_sync_error!(message)
    update!(last_synced_at: Time.current, last_sync_status: 'error', last_sync_error: message.to_s.truncate(500))
  end

  private

  # Ads Manager shows the id as "act_123…"; operators paste it either way.
  def normalize_external_id
    self.external_id = external_id.to_s.strip.delete_prefix('act_').presence
  end
end
