# The automation rules that point at clinic pipeline stages, in a condition
# (`pipeline_stage_id`) or an action (`move_to_pipeline_stage`). A stage in
# use cannot be deleted; deleting a whole pipeline lists them as a warning.
class Pipelines::AutomationUsage
  pattr_initialize [:account!, :stage_ids!]

  def rules
    ids = Array(stage_ids).map(&:to_i)
    account.automation_rules.order(:name).select { |rule| uses_any?(rule, ids) }
  end

  private

  def uses_any?(rule, ids)
    condition_ids = Array(rule.conditions).select { |condition| condition['attribute_key'] == 'pipeline_stage_id' }
                                          .flat_map { |condition| Array(condition['values']) }
    action_ids = Array(rule.actions).select { |action| action['action_name'] == 'move_to_pipeline_stage' }
                                    .map { |action| Array(action['action_params']).first }
    (condition_ids + action_ids).map(&:to_i).intersect?(ids)
  end
end
