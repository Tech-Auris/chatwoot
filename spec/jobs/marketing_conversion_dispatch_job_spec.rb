require 'rails_helper'

RSpec.describe MarketingConversionDispatchJob do
  let(:account) { create(:account) }
  let(:conversion_event) { create(:conversion_event, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    # Job hands off to Marketing::MetaCapiDispatcher which does the real
    # network call — that's tested in its own spec, so mock it here to keep
    # the job spec focused on find_or_create + dispatch routing.
    allow(Marketing::MetaCapiDispatcher).to receive(:new).and_return(instance_double(Marketing::MetaCapiDispatcher, perform: nil))
  end

  describe '#perform' do
    it 'creates a pending dispatch row idempotently keyed by (provider, event_id) and hands it off to the Meta dispatcher' do
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
      expect(Marketing::MetaCapiDispatcher).to have_received(:new).with(dispatch: row)
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

      expect do
        described_class.perform_now(conversion_event_id: conversion_event_id,
                                    conversation_id: conversation.id, provider: 'meta_capi')
      end.not_to change(ConversionEventDispatch, :count)
    end

    # Google Ads Enhanced Conversions dispatcher is wired in PR D. Until then
    # the job creates the row but the dispatch stays pending — the follow-up
    # PR's dispatcher will pick it up from the `retryable` scope.
    it 'leaves the row pending for google_ads_enhanced (no dispatcher yet)' do
      described_class.new.perform(conversion_event_id: conversion_event.id,
                                  conversation_id: conversation.id, provider: 'google_ads_enhanced')

      expect(ConversionEventDispatch.last).to have_attributes(provider: 'google_ads_enhanced', status: 'pending')
      expect(Marketing::MetaCapiDispatcher).not_to have_received(:new)
    end
  end
end
