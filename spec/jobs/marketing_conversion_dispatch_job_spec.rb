require 'rails_helper'

RSpec.describe MarketingConversionDispatchJob do
  let(:account) { create(:account) }
  let(:conversion_event) { create(:conversion_event, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  # PR B: job is a stub that only persists the dispatch row. The actual Meta
  # / Google POSTs land in PRs C and D, respectively.
  describe '#perform' do
    it 'creates a pending dispatch row idempotently keyed by (provider, event_id)' do
      expect do
        described_class.new.perform(
          conversion_event_id: conversion_event.id,
          conversation_id: conversation.id,
          provider: 'meta_capi'
        )
      end.to change(ConversionEventDispatch, :count).by(1)

      row = ConversionEventDispatch.last
      expect(row.provider).to eq('meta_capi')
      expect(row.status).to eq('pending')
      expect(row.event_id).to eq(
        ConversionEventDispatch.build_event_id(
          conversion_event_id: conversion_event.id,
          conversation_id: conversation.id,
          provider: 'meta_capi'
        )
      )
    end

    it 'is idempotent on retry — a second run reuses the same row' do
      described_class.new.perform(conversion_event_id: conversion_event.id,
                                  conversation_id: conversation.id, provider: 'meta_capi')

      expect do
        described_class.new.perform(conversion_event_id: conversion_event.id,
                                    conversation_id: conversation.id, provider: 'meta_capi')
      end.not_to change(ConversionEventDispatch, :count)
    end

    it 'discards silently when the conversion_event has been deleted between enqueue and run' do
      conversion_event_id = conversion_event.id
      conversion_event.destroy!

      # discard_on ActiveRecord::RecordNotFound at the ApplicationJob layer —
      # the job class swallows the error rather than raising forever.
      expect do
        described_class.perform_now(conversion_event_id: conversion_event_id,
                                    conversation_id: conversation.id, provider: 'meta_capi')
      end.not_to change(ConversionEventDispatch, :count)
    end
  end
end
