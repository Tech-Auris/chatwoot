# Central fan-out for Fase 2 triggers. A caller says "this conversation just
# hit trigger T with config C" and we resolve every enabled `ConversionEvent`
# that matches, then enqueue one dispatch job per (event, provider) pair the
# account has an active integration for — and, for Meta, one per pixel in
# `test_mode` or `active`, each sent with its own token.
#
# Providers gated at two levels — cheap DB checks that we don't overload
# Sidekiq with jobs the dispatcher would refuse:
#   1. `ConversionEvent.<provider>_event_name` must be present (no name = no
#      intent to send to that provider).
#   2. Meta needs at least one pixel in `test_mode` or `active`; Google needs
#      its `MarketingIntegration` in `test_mode` or `active`.
#
# Fase 2 · PR B: the enqueued `MarketingConversionDispatchJob` is a stub that
# only persists the dispatch row. PR C/D wire the actual Meta/Google POSTs.
class Marketing::TriggerConversionEventsService
  pattr_initialize [:conversation!, :trigger_type!, { trigger_config: {}, explicit_event_ids: nil }]

  def perform
    return if conversation.blank?

    matching_events.each do |event|
      meta_pixel_ids.each { |pixel_id| enqueue(event, 'meta_capi', pixel_id) } if event.meta_event_name.present?
      enqueue(event, 'google_ads_enhanced') if event.google_event_name.present? && google_active?
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

  def enqueue(event, provider, marketing_pixel_id = nil)
    MarketingConversionDispatchJob.perform_later(
      conversion_event_id: event.id,
      conversation_id: conversation.id,
      provider: provider,
      marketing_pixel_id: marketing_pixel_id
    )
  end

  def meta_pixel_ids
    @meta_pixel_ids ||= account.marketing_pixels.sending.pluck(:id)
  end

  def google_active?
    account.marketing_integrations.google_ads_enhanced.exists?(status: %i[test_mode active])
  end
end
