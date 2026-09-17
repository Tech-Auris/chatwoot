require 'rails_helper'

RSpec.describe ConversionEventDispatch do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversion_event) }
    it { is_expected.to belong_to(:conversation) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:provider).with_values(meta_capi: 0, google_ads_enhanced: 1) }
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, sent: 1, failed: 2, permanently_failed: 3) }
  end

  describe '.build_event_id' do
    # Stable idempotency key — same (event, conversation, provider) yields the
    # same string every call, so the dispatcher can safely do a
    # find_or_create_by(event_id:, provider:) on retry.
    it 'is deterministic across calls' do
      first = described_class.build_event_id(conversion_event_id: 5, conversation_id: 99, provider: 'meta_capi')
      second = described_class.build_event_id(conversion_event_id: 5, conversation_id: 99, provider: 'meta_capi')
      expect(first).to eq(second)
    end

    it 'namespaces the provider so meta and google dispatches never collide on the same event+conversation' do
      meta = described_class.build_event_id(conversion_event_id: 5, conversation_id: 99, provider: 'meta_capi')
      google = described_class.build_event_id(conversion_event_id: 5, conversation_id: 99, provider: 'google_ads_enhanced')
      expect(meta).not_to eq(google)
    end
  end

  describe 'idempotency guard' do
    # Unique index on (provider, event_id) — Rails validation echoes it so the
    # UI (and the dispatcher on retry) can surface a friendly message instead
    # of the raw PG error.
    it 'rejects a duplicate event_id under the same provider' do
      first = create(:conversion_event_dispatch)
      dup = build(:conversion_event_dispatch,
                  account: first.account, conversion_event: first.conversion_event,
                  conversation: first.conversation, provider: first.provider,
                  event_id: first.event_id)
      expect(dup).to be_invalid
      expect(dup.errors[:event_id]).to be_present
    end

    it 'allows the same event_id under a different provider' do
      first = create(:conversion_event_dispatch, provider: :meta_capi)
      other = build(:conversion_event_dispatch,
                    account: first.account, conversion_event: first.conversion_event,
                    conversation: first.conversation, provider: :google_ads_enhanced,
                    event_id: first.event_id)
      expect(other).to be_valid
    end
  end

  describe '.retryable' do
    let(:account) { create(:account) }
    let(:conversion_event) { create(:conversion_event, account: account) }
    let(:conversation) { create(:conversation, account: account) }

    it 'includes pending and failed rows, excludes sent and permanently_failed' do
      pending = create(:conversion_event_dispatch, account: account, conversion_event: conversion_event, conversation: conversation,
                                                   status: :pending, provider: :meta_capi,
                                                   event_id: 'evt-pending')
      failed = create(:conversion_event_dispatch, account: account, conversion_event: conversion_event, conversation: conversation,
                                                  status: :failed, provider: :google_ads_enhanced,
                                                  event_id: 'evt-failed')
      _sent = create(:conversion_event_dispatch, account: account, conversion_event: conversion_event, conversation: conversation,
                                                 status: :sent, provider: :meta_capi,
                                                 event_id: 'evt-sent')
      _permanent = create(:conversion_event_dispatch, account: account, conversion_event: conversion_event, conversation: conversation,
                                                      status: :permanently_failed, provider: :google_ads_enhanced,
                                                      event_id: 'evt-perm')

      expect(described_class.retryable).to contain_exactly(pending, failed)
    end
  end
end
