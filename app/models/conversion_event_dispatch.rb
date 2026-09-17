# Single attempt to push a conversion event downstream. Idempotency + history
# for the two providers we integrate with in Fase 2 (Meta CAPI, Google Ads
# Enhanced Conversions).
#
# `event_id` is the stable dedup key. Same conversation + same conversion
# event + same provider yields the same event_id, so a retry (Sidekiq
# exponential backoff) reuses the existing row and Meta/Google dedup by that
# id on their side. Format:
#   "cev-{conversion_event_id}-conv-{conversation_id}-{provider_shortname}"
#
# `payload` and `response` are jsonb — dispatcher writes the normalized body
# it sent (with hashed PII already applied) before the network call so a
# `permanently_failed` row still shows what was attempted; the provider
# response lands in `response` after the call resolves.
#
# Status transitions:
#   pending → sent | failed | permanently_failed
#   failed  → sent | permanently_failed (Sidekiq retries)
# == Schema Information
#
# Table name: conversion_event_dispatches
#
#  id                  :bigint           not null, primary key
#  attempts            :integer          default(0), not null
#  last_attempted_at   :datetime
#  payload             :jsonb            not null
#  provider            :integer          not null
#  response            :jsonb            not null
#  status              :integer          default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  conversation_id     :bigint           not null
#  conversion_event_id :bigint           not null
#  event_id            :string           not null
#
# Indexes
#
#  idx_on_conversion_event_id_conversation_id_43f6b9e96e       (conversion_event_id,conversation_id)
#  index_conversion_event_dispatches_on_account_id_and_status  (account_id,status)
#  index_conversion_event_dispatches_on_conversation_id        (conversation_id)
#  index_conversion_event_dispatches_on_conversion_event_id    (conversion_event_id)
#  index_dispatches_on_provider_and_event_id                   (provider,event_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (conversion_event_id => conversion_events.id)
#
class ConversionEventDispatch < ApplicationRecord
  PROVIDERS = { meta_capi: 0, google_ads_enhanced: 1 }.freeze
  STATUSES = { pending: 0, sent: 1, failed: 2, permanently_failed: 3 }.freeze

  enum provider: PROVIDERS
  enum status: STATUSES

  belongs_to :account
  belongs_to :conversion_event
  belongs_to :conversation

  validates :event_id, presence: true, uniqueness: { scope: :provider }

  scope :retryable, -> { where(status: %i[pending failed]) }

  # Stable identifier for (event, conversation, provider). Kept as a class
  # method so a caller can compute it BEFORE creating the row (idempotent
  # `find_or_create_by(event_id:, provider:)`) without instantiating the
  # dispatch first.
  def self.build_event_id(conversion_event_id:, conversation_id:, provider:)
    short = provider.to_s == 'meta_capi' ? 'meta' : 'gads'
    "cev-#{conversion_event_id}-conv-#{conversation_id}-#{short}"
  end
end
