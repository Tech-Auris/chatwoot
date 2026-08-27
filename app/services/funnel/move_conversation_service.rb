class Funnel::MoveConversationService
  include Events::Types

  Result = Struct.new(:conversation, :previous_stage, :new_stage, :change, keyword_init: true)

  pattr_initialize [:account!, :conversation_display_id!,
                    { target_stage_name: nil, target_stage_id: nil, user: nil, reason: nil, source: 'web', loss_reason_id: nil }]

  def perform
    validate!

    previous_stage = conversation.funnel_stage

    ActiveRecord::Base.transaction do
      apply_stage_change!
      record_audit!(previous_stage&.name)
    end

    dispatch_funnel_updated_event(previous_stage)

    Result.new(
      conversation: conversation,
      previous_stage: previous_stage&.name,
      new_stage: target_stage.name,
      change: @change
    )
  end

  private

  def validate!
    raise ActiveRecord::RecordNotFound, 'Conversation not found' unless conversation

    validate_target_stage!
    raise ArgumentError, "Stage '#{target_stage.name}' requires a loss_reason_id" if loss_reason_required_but_missing?
    raise ArgumentError, "loss_reason_id #{loss_reason_id} is invalid" if loss_reason_id_provided_but_invalid?
  end

  def validate_target_stage!
    raise ArgumentError, 'Informe a etapa de destino' if target_stage_name.blank? && target_stage_id.blank?
    raise ArgumentError, "Stage '#{target_stage_name || target_stage_id}' is not active" unless target_stage
  end

  def conversation
    @conversation ||= account.conversations.find_by(display_id: conversation_display_id)
  end

  # Callers may point at the stage by id or by name. The id is the reliable
  # handle — renaming a stage would otherwise break a move already in flight —
  # but the name is kept because the kanban and the automations still use it.
  def target_stage
    @target_stage ||= if target_stage_id.present?
                        FunnelStage.active.find_by(id: target_stage_id)
                      else
                        FunnelStage.active.find_by(name: target_stage_name)
                      end
  end

  def loss_reason
    return nil if loss_reason_id.blank?

    @loss_reason ||= LossReason.active.find_by(id: loss_reason_id)
  end

  def loss_reason_required_but_missing?
    target_stage.requires_loss_reason? && loss_reason_id.blank?
  end

  def loss_reason_id_provided_but_invalid?
    loss_reason_id.present? && loss_reason.nil?
  end

  def apply_stage_change!
    conversation.update!(funnel_stage_id: target_stage.id)
  end

  def record_audit!(previous_stage_name)
    @change = account.funnel_stage_changes.create!(
      inbox_id: conversation.inbox_id,
      contact_id: conversation.contact_id,
      conversation_id: conversation.id,
      previous_stage: previous_stage_name,
      new_stage: target_stage.name,
      cycle: next_cycle_for(previous_stage_name),
      reason: reason,
      source: source,
      user: user,
      loss_reason: loss_reason
    )
  end

  def next_cycle_for(previous_stage_name)
    return 1 if previous_stage_name.blank?

    last_cycle = account.funnel_stage_changes
                        .where(conversation_id: conversation.id, new_stage: target_stage.name)
                        .maximum(:cycle) || 0
    last_cycle + 1
  end

  def dispatch_funnel_updated_event(previous_stage)
    Rails.configuration.dispatcher.dispatch(
      FUNNEL_UPDATED,
      Time.zone.now,
      conversation: conversation,
      previous_stage: previous_stage,
      new_stage: target_stage,
      reason: reason,
      source: source,
      user: user,
      change: @change,
      loss_reason: loss_reason
    )
  end
end
