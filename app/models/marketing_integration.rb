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

  # `ad_account_id` is optional — only the spend-sync path uses it, and only
  # when the operator wants CPL/ROAS in the Analytics report. CAPI itself
  # never touches it. Format: numeric ("1234567890"), the caller prefixes
  # with "act_" when it hits the Insights endpoint.
  META_CAPI_KEYS = %w[pixel_id access_token test_event_code ad_account_id].freeze
  # `conversion_action_id` is the numeric id of the Google Ads Conversion
  # Action (Configurações → Conversões → click into an action → the id shows in
  # the URL). The gtag-oriented `conversion_id` / `conversion_label` fields
  # don't apply to the offline upload API — the resource name is built from
  # (customer_id, conversion_action_id).
  #
  # `login_customer_id` is optional; only required when the developer token
  # is registered under a Google Ads MCC that isn't the same as `customer_id`.
  GOOGLE_ADS_KEYS = %w[customer_id conversion_action_id developer_token oauth_refresh_token login_customer_id].freeze

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
    required = meta_capi? ? %w[pixel_id access_token] : %w[customer_id conversion_action_id developer_token oauth_refresh_token]
    missing = required.select { |k| credentials[k].to_s.strip.empty? }
    return if missing.empty?

    errors.add(:credentials, "missing required keys: #{missing.join(', ')}")
  end
end
