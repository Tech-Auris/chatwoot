# Deletes a stage of a clinic pipeline. Ganho / Perdido stay, and so does the
# last stage of the clinic's own. The contacts on the stage go to the stage
# the user picked, each with its move in the history.
class Pipelines::DestroyStageService
  pattr_initialize [:stage!, { move_to_stage: nil, user: nil }]

  def perform
    validate!
    ActiveRecord::Base.transaction do
      move_entries! if entries.exists?
      stage.destroy!
    end
  end

  private

  def entries
    stage.entries
  end

  def validate!
    raise CustomExceptions::Pipeline.new(key: :closing_stage_delete) if stage.closing?
    raise CustomExceptions::Pipeline.new(key: :last_open_stage) if stage.pipeline.stages.open.count <= 1
    raise CustomExceptions::Pipeline.new(key: :stage_in_automation, rules: rules_using_stage.map(&:name).join(', ')) if rules_using_stage.any?
    raise CustomExceptions::Pipeline.new(key: :move_target_required) if entries.exists? && !valid_target?
  end

  def rules_using_stage
    @rules_using_stage ||= Pipelines::AutomationUsage.new(account: stage.pipeline.account, stage_ids: [stage.id]).rules
  end

  def valid_target?
    move_to_stage&.open? && move_to_stage.pipeline_id == stage.pipeline_id && move_to_stage.id != stage.id
  end

  def move_entries!
    now = Time.current
    events = entries.pluck(:id).map do |entry_id|
      { pipeline_entry_id: entry_id, pipeline_id: stage.pipeline_id, from_stage_id: stage.id, to_stage_id: move_to_stage.id,
        user_id: user&.id, source: 'web', created_at: now }
    end
    PipelineEntryEvent.insert_all!(events) # rubocop:disable Rails/SkipsModelValidations
    entries.update_all(pipeline_stage_id: move_to_stage.id, stage_entered_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
  end
end
