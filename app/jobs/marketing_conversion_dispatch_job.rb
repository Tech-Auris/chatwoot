# Persists a `ConversionEventDispatch` for a matched trigger. Idempotent via
# `event_id` so a Sidekiq retry (default exponential backoff) does not create
# a duplicate row.
#
# PR B stub — only writes the DB row and logs. The actual Meta CAPI POST
# (PR C) and the Google Ads Enhanced Conversions upload (PR D) plug into
# `dispatch_via_provider` in follow-up PRs.
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

  # Stubbed for PR B. PR C wires Meta CAPI; PR D wires Google Ads.
  # Leaving the row in `pending` on purpose so the follow-up worker knows
  # what still needs to be sent when the real dispatcher ships.
  def dispatch_via_provider(dispatch)
    Rails.logger.info(
      "[MarketingConversionDispatchJob] dispatch ##{dispatch.id} pending — " \
      "provider=#{dispatch.provider} event_id=#{dispatch.event_id}"
    )
  end
end
