class AutomationRuleListener < BaseListener
  def conversation_updated(event)
    process_conversation_event(event, 'conversation_updated')
  end

  def conversation_created(event)
    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    process_conversation_event(event, 'conversation_resolved')
  end

  # `funnel.updated` fires from Funnel::MoveConversationService whenever a
  # conversation moves between funnel stages. Reuse the standard
  # conversation-scoped pipeline so any condition (funnel_stage_id
  # included) evaluates like it does on conversation_updated. A move writes
  # only funnel_stage_id, which dispatches no conversation_updated, so it also
  # arms the inactivity waits (a move made by a rule is armed on the way in).
  def funnel_updated(event)
    process_conversation_event(event, 'funnel_updated')
    arm_inactivity(event) unless performed_by_automation?(event)
  end

  def message_created(event)
    process_message_event(event, 'message_created')
    arm_inactivity(event)
  end

  # Only rules whose trigger is "Message Edited" answer an edit: re-running message_created rules would
  # have an auto-reply answering a typo correction.
  def message_edited(event)
    process_message_event(event, 'message_edited')
    arm_inactivity(event)
  end

  private

  def process_message_event(event, event_name)
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?(event_name, account)

    rules = current_account_rules(event_name, account)

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, message.conversation,
                                                                        { message: message, changed_attributes: changed_attributes }).perform
      execute_rule(rule, account, message.conversation, message: message) if conditions_match.present?
    end
  end

  def process_conversation_event(event, event_name)
    return arm_inactivity(event) if performed_by_automation?(event)

    auto_reply_skip_events = %w[conversation_created conversation_opened]
    return if auto_reply_skip_events.include?(event_name) && ignore_auto_reply_event?(event)

    conversation = event.data[:conversation]
    account = conversation.account
    changed_attributes = event.data[:changed_attributes]

    rules = conversation_rules(event_name, account)
    return if rules.blank?

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: changed_attributes }).perform
      execute_rule(rule, account, conversation, at: event.timestamp) if conditions_match.present?
    end
  end

  # A delayed conversation rule reads as "the conversation has been in this status for N minutes",
  # so a conversation created in that status must arm it too. Creation never dispatches
  # CONVERSATION_UPDATED, and both paths key the episode on the same status_changed_at, so a later
  # update arming the same episode is deduped by the unique index.
  def conversation_rules(event_name, account)
    rules = current_account_rules(event_name, account)
    return rules unless event_name == 'conversation_created'

    rules + current_account_rules('conversation_updated', account).where.not(execution_delay: nil)
  end

  # Delayed rules record a pending execution instead of acting; the sweep re-checks and
  # runs them at due time. Flag off means no arming and no immediate fallback — a delayed
  # message silently becoming instant is worse than skipping.
  def execute_rule(rule, account, conversation, message: nil, at: nil)
    if rule.execution_delay.present?
      return unless account.feature_enabled?('delayed_automations')

      AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation, message: message, at: at)
    else
      ::AutomationRules::ActionService.new(rule, account, conversation).perform
    end
  end

  def rule_present?(event_name, account)
    return false if account.blank?

    current_account_rules(event_name, account).any?
  end

  def current_account_rules(event_name, account)
    AutomationRule.where(
      event_name: event_name,
      account_id: account.id,
      active: true
    )
  end

  # A message is the commonest activity there is, and neither its arrival nor its edit dispatches a
  # conversation event: last_activity_at is written with update_columns on a create, and an edit
  # moves no conversation timestamp at all. A wait on inactivity is conversation-level, so it arms
  # from here or it would fire on a conversation somebody is writing in.
  # Who wrote it is handed over rather than filtered here: which automation's writing counts as the
  # conversation being alive is the wait's own question, and it is answered where it is asked. That
  # is also why a rule's own conversation event reaches this after the early return above: its
  # writing is no reason to run the rules again, but it is still activity, and a wait on silence
  # that already ran is terminal, so no sweep will read it. The arm is the only thing left that can.
  def arm_inactivity(event)
    message = event.data[:message]
    return if message && (message.activity? || message.auto_reply_email?)

    conversation = message&.conversation || event.data[:conversation]
    ::AutomationRules::InactivityArmingService.new(
      conversation, message: message, performed_by: event.data[:performed_by], at: event.timestamp
    ).perform
  end

  def performed_by_automation?(event)
    event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
  end

  def ignore_auto_reply_event?(event)
    conversation = event.data[:conversation]
    conversation.additional_attributes['auto_reply'].present?
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) || message.activity? || message.auto_reply_email?
  end
end
