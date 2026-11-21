# Moves a pipeline entry to another stage of its pipeline, the same way
# Funnel::MoveConversationService moves a conversation on the Agendamento.
# Ganho / Perdido close the entry; Perdido needs a loss reason. Taking an entry
# out of Ganho / Perdido reopens it, unless the contact already entered the
# pipeline again.
class Pipelines::MoveEntryService
  include Events::Types

  pattr_initialize [:entry!, :stage!, { user: nil, source: 'web', reason: nil, loss_reason_id: nil }]

  def perform
    return entry if stage.id == entry.pipeline_stage_id

    validate!
    previous_stage = entry.stage
    ActiveRecord::Base.transaction do
      apply_move!
      record_event!(previous_stage)
    end
    Rails.configuration.dispatcher.dispatch(PIPELINE_ENTRY_UPDATED, Time.zone.now, entry: entry, previous_stage: previous_stage,
                                                                                   new_stage: stage, user: user)
    entry
  rescue ActiveRecord::RecordNotUnique
    raise CustomExceptions::Pipeline.new(key: :already_open)
  end

  private

  def validate!
    raise CustomExceptions::Pipeline.new(key: :stage_mismatch) unless stage.pipeline_id == entry.pipeline_id
    raise CustomExceptions::Pipeline.new(key: :loss_reason_required) if stage.lost? && loss_reason.nil?
  end

  def apply_move!
    now = Time.current
    entry.update!(
      stage: stage,
      stage_entered_at: now,
      closed_at: stage.open? ? nil : (entry.closed_at || now),
      loss_reason: stage.lost? ? loss_reason : nil
    )
  end

  def record_event!(previous_stage)
    entry.events.create!(pipeline: entry.pipeline, from_stage: previous_stage, to_stage: stage, user: user,
                         source: source, reason: reason, loss_reason: loss_reason)
  end

  def loss_reason
    return if loss_reason_id.blank?

    @loss_reason ||= LossReason.active.find_by(id: loss_reason_id)
  end
end
