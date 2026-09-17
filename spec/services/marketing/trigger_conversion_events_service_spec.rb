require 'rails_helper'

RSpec.describe Marketing::TriggerConversionEventsService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:meta_integration) do
    create(:marketing_integration, account: account, provider: :meta_capi, status: :test_mode)
  end

  describe '#perform' do
    context 'when the funnel_stage_reached trigger matches a configured event' do
      let!(:event) do
        create(:conversion_event, :funnel_stage_reached, account: account,
                                                         trigger_config: { 'funnel_stage_id' => 42 },
                                                         meta_event_name: 'Schedule')
      end

      it 'enqueues a MarketingConversionDispatchJob per matched event/provider pair' do
        expect do
          described_class.new(
            conversation: conversation,
            trigger_type: 'funnel_stage_reached',
            trigger_config: { 'funnel_stage_id' => 42 }
          ).perform
        end.to have_enqueued_job(MarketingConversionDispatchJob).with(
          conversion_event_id: event.id, conversation_id: conversation.id, provider: 'meta_capi'
        )
      end

      it 'ignores events that target a different funnel stage' do
        _other = create(:conversion_event, :funnel_stage_reached, account: account,
                                                                  trigger_config: { 'funnel_stage_id' => 999 },
                                                                  meta_event_name: 'Purchase')

        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).to have_been_enqueued.once
      end
    end

    context 'when the label_added trigger matches a configured event' do
      let!(:event) do
        create(:conversion_event, :label_added, account: account,
                                                trigger_config: { 'label' => 'converteu' },
                                                meta_event_name: 'Lead')
      end

      it 'enqueues a dispatch job for the matching label' do
        expect do
          described_class.new(
            conversation: conversation,
            trigger_type: 'label_added',
            trigger_config: { 'label' => 'converteu' }
          ).perform
        end.to have_enqueued_job(MarketingConversionDispatchJob).with(
          conversion_event_id: event.id, conversation_id: conversation.id, provider: 'meta_capi'
        )
      end
    end

    context 'when the automation_action trigger passes explicit event ids' do
      let!(:event) do
        create(:conversion_event, account: account, trigger_type: :automation_action,
                                  trigger_config: {}, meta_event_name: 'CompleteRegistration')
      end

      before do
        # Second event exists to prove explicit_event_ids is a filter, not a
        # fan-out; reading through it in the assertion is enough — no let!.
        create(:conversion_event, account: account, trigger_type: :automation_action,
                                  trigger_config: {}, meta_event_name: 'SubmitApplication')
      end

      it 'enqueues only the events referenced by id' do
        described_class.new(
          conversation: conversation,
          trigger_type: 'automation_action',
          explicit_event_ids: [event.id]
        ).perform

        expect(MarketingConversionDispatchJob).to have_been_enqueued.once.with(
          conversion_event_id: event.id, conversation_id: conversation.id, provider: 'meta_capi'
        )
      end

      it 'refuses to fan out when trigger_type is automation_action without ids' do
        described_class.new(
          conversation: conversation,
          trigger_type: 'automation_action'
        ).perform

        expect(MarketingConversionDispatchJob).not_to have_been_enqueued
      end
    end

    context 'when gating providers by integration + event-name presence' do
      let!(:event) do
        create(:conversion_event, :funnel_stage_reached, account: account,
                                                         trigger_config: { 'funnel_stage_id' => 42 },
                                                         meta_event_name: 'Schedule',
                                                         google_event_name: 'book_appointment')
      end

      it 'skips a provider when the account has no active integration for it' do
        # Only meta_capi is set up (default in the outer before block); google
        # has no integration so no google dispatch job is enqueued.
        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).to have_been_enqueued.once.with(
          conversion_event_id: event.id, conversation_id: conversation.id, provider: 'meta_capi'
        )
      end

      it 'fires both providers when both integrations are active' do
        create(:marketing_integration, :google_ads, account: account, status: :active)

        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).to have_been_enqueued.twice
      end

      it 'skips a provider when the ConversionEvent has no event name set for it' do
        event.update!(google_event_name: nil)
        create(:marketing_integration, :google_ads, account: account, status: :active)

        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).to have_been_enqueued.once.with(
          conversion_event_id: event.id, conversation_id: conversation.id, provider: 'meta_capi'
        )
      end

      # Disabled integrations must not fire — the operator turned them off on
      # purpose, and firing anyway would be surprising when they re-enable.
      it 'skips a disabled integration' do
        meta_integration.update!(status: :disabled)

        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).not_to have_been_enqueued
      end
    end

    context 'when the conversion event is disabled' do
      it 'is skipped even if the trigger config matches' do
        create(:conversion_event, :funnel_stage_reached, account: account,
                                                         trigger_config: { 'funnel_stage_id' => 42 },
                                                         meta_event_name: 'Schedule',
                                                         enabled: false)

        described_class.new(
          conversation: conversation,
          trigger_type: 'funnel_stage_reached',
          trigger_config: { 'funnel_stage_id' => 42 }
        ).perform

        expect(MarketingConversionDispatchJob).not_to have_been_enqueued
      end
    end
  end
end
