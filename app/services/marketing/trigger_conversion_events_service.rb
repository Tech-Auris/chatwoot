# Central fan-out for Fase 2 triggers. A caller says "this conversation just
# hit trigger T with config C" and we resolve every enabled `ConversionEvent`
# that matches, then enqueue one dispatch job per (event, provider) pair the
# account has an active integration for.
#
# Providers gated at two levels — cheap DB checks that we don't overload
# Sidekiq with jobs the dispatcher would refuse:
#   1. `ConversionEvent.<provider>_event_name` must be present (no name = no
#      intent to send to that provider).
#   2. The account must have a `MarketingIntegration` for that provider in
#      `test_mode` or `active` (disabled integrations don't fire).
#
# Fase 2 · PR B: the enqueued `MarketingConversionDispatchJob` is a stub that
# only persists the dispatch row. PR C/D wire the actual Meta/Google POSTs.
class Marketing::TriggerConversionEventsService
  PROVIDER_EVENT_COLUMNS = {
    'meta_capi' => :meta_event_name,
    'google_ads_enhanced' => :google_event_name
  }.freeze

  pattr_initialize [:conversation!, :trigger_type!, { trigger_config: {}, explicit_event_ids: nil }]

  def perform
    return if conversation.blank?

    matching_events.each do |event|
      enabled_providers_for(event).each do |provider|
        MarketingConversionDispatchJob.perform_later(
          conversion_event_id: event.id,
          conversation_id: conversation.id,
          provider: provider
        )
      end
    end
  end

  private

  def account
    @account ||= conversation.account
  end

  # `explicit_event_ids` short-circuits trigger matching — the automation
  # action "Trigger conversion event" passes the ids the operator picked,
  # regardless of trigger_type.
  def matching_events
    return account.conversion_events.enabled.where(id: explicit_event_ids) if explicit_event_ids.present?

    scope = account.conversion_events.enabled
    case trigger_type.to_s
    when 'funnel_stage_reached'
      scope.for_funnel_stage(trigger_config[:funnel_stage_id] || trigger_config['funnel_stage_id'])
    when 'label_added'
      scope.for_label(trigger_config[:label] || trigger_config['label'])
    else
      # Unknown trigger + automation_action without explicit ids both collapse
      # to nothing on purpose (automation-action without ids is a misuse).
      ConversionEvent.none
    end
  end

  def enabled_providers_for(event)
    # `pluck(:provider)` returns the string enum keys under Rails 7; no need
    # to reverse-lookup by integer.
    active_provider_names = account.marketing_integrations
                                   .where(status: %i[test_mode active])
                                   .pluck(:provider)

    active_provider_names.select do |provider|
      column = PROVIDER_EVENT_COLUMNS[provider]
      column && event.public_send(column).present?
    end
  end
end
