# Persists a `ConversionEventDispatch` for a matched trigger and hands it to
# the right provider dispatcher. Idempotent via `event_id` — a Sidekiq
# retry (default exponential backoff) reuses the same row and Meta/Google
# dedup on their side.
#
# Meta CAPI wired in this PR; Google Ads Enhanced Conversions ships in PR D.
class MarketingConversionDispatchJob < ApplicationJob
  queue_as :default

  # Sidekiq default is 25 retries with exponential backoff — plenty for
  # transient network / rate-limit failures. Explicit override is only
  # needed if we want a different curve; keeping the default.
  discard_on ActiveRecord::RecordNotFound

  def perform(conversion_event_id:, conversation_id:, provider:)
    conversion_event = ConversionEvent.find(conversion_event_id)
    conversation = Conversation.find(conversation_id)

    dispatch = ConversionEventDispatch.find_or_create_by!(
      provider: provider,
      event_id: ConversionEventDispatch.build_event_id(
        conversion_event_id: conversion_event.id,
        conversation_id: conversation.id,
        provider: provider
      )
    ) do |row|
      row.account = conversation.account
      row.conversion_event = conversion_event
      row.conversation = conversation
      row.status = :pending
    end

    dispatch_via_provider(dispatch)
  end

  private

  def dispatch_via_provider(dispatch)
    case dispatch.provider
    when 'meta_capi'
      ::Marketing::MetaCapiDispatcher.new(dispatch: dispatch).perform
    when 'google_ads_enhanced'
      # Wired in PR D. The dispatch row stays `pending` until then.
      Rails.logger.info("[MarketingConversionDispatchJob] google_ads_enhanced dispatcher not wired yet — dispatch ##{dispatch.id}")
    end
  end
end
