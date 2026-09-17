# Per-account credentials for a marketing-conversion provider. Two supported
# providers today (Fase 2):
#
# * `meta_capi` — Meta Conversions API. Credentials shape:
#     { "pixel_id" => "...", "access_token" => "...", "test_event_code" => nil }
# * `google_ads_enhanced` — Google Ads Enhanced Conversions. Credentials shape:
#     { "customer_id" => "...", "conversion_id" => "...", "conversion_label" => "...",
#       "developer_token" => "...", "oauth_refresh_token" => "..." }
#
# Credentials serialize to JSON in `credentials_ciphertext` and encrypt at
# rest via Rails 7 `encrypts`, gated by `Chatwoot.encryption_configured?`
# (same guard the rest of the fork uses on Hook/Channel::* — deploys without
# encryption keys still work, they just store plaintext until keys land).
#
# One integration per (account, provider); the unique index guards it and the
# UI ends up as an upsert.
# == Schema Information
#
# Table name: marketing_integrations
#
#  id                     :bigint           not null, primary key
#  credentials_ciphertext :text
#  provider               :integer          not null
#  status                 :integer          default("disabled"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
# Indexes
#
#  index_marketing_integrations_on_account_and_provider  (account_id,provider) UNIQUE
#  index_marketing_integrations_on_status                (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class MarketingIntegration < ApplicationRecord
  PROVIDERS = { meta_capi: 0, google_ads_enhanced: 1 }.freeze
  STATUSES = { disabled: 0, test_mode: 1, active: 2 }.freeze

  META_CAPI_KEYS = %w[pixel_id access_token test_event_code].freeze
  GOOGLE_ADS_KEYS = %w[customer_id conversion_id conversion_label developer_token oauth_refresh_token].freeze

  encrypts :credentials_ciphertext if Chatwoot.encryption_configured?

  enum provider: PROVIDERS
  enum status: STATUSES

  belongs_to :account

  validates :account_id, uniqueness: { scope: :provider }
  validate :required_credentials_present, if: -> { active? || test_mode? }

  def credentials
    return {} if credentials_ciphertext.blank?

    JSON.parse(credentials_ciphertext)
  rescue JSON::ParserError
    {}
  end

  def credentials=(hash)
    self.credentials_ciphertext = hash.is_a?(Hash) ? hash.to_json : nil
  end

  private

  def required_credentials_present
    required = meta_capi? ? %w[pixel_id access_token] : %w[customer_id conversion_id developer_token oauth_refresh_token]
    missing = required.select { |k| credentials[k].to_s.strip.empty? }
    return if missing.empty?

    errors.add(:credentials, "missing required keys: #{missing.join(', ')}")
  end
end
