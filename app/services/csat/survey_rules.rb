# Whether a resolved conversation gets the CSAT survey, by the inbox's survey
# rule: conditions on the conversation (labels, funnel stage, loss reason)
# joined by E / OU, with E binding tighter, like the automation rules. No
# condition (or none filled in) sends to everyone.
class Csat::SurveyRules
  NEGATIVE_OPERATORS = %w[not_equal_to does_not_contain].freeze

  pattr_initialize [:conversation!, :survey_rules]

  def allowed?
    return true if conditions.empty?

    groups = conditions.slice_after { |condition| condition['query_operator'].to_s.casecmp?('or') }
    groups.any? { |group| group.all? { |condition| met?(condition) } }
  end

  private

  def met?(condition)
    matched = conversation_values_for(condition['attribute_key']).intersect?(Array(condition['values']).map(&:to_s))
    NEGATIVE_OPERATORS.include?(condition['filter_operator']) ? !matched : matched
  end

  def conversation_values_for(attribute_key)
    case attribute_key
    when 'labels' then conversation.label_list
    when 'funnel_stage_id' then [conversation.funnel_stage_id.to_s]
    when 'loss_reason_id' then [conversation.loss_reason_id.to_s]
    else []
    end
  end

  # Rules saved before the conditions list were a single label rule
  # (`operator` + `values`); they keep working as that one condition.
  def conditions
    @conditions ||= begin
      rules = survey_rules || {}
      list = rules['conditions'] || [{ 'attribute_key' => 'labels', 'filter_operator' => rules['operator'] || 'contains',
                                       'values' => rules['values'] }]
      list.select { |condition| Array(condition['values']).any? }
    end
  end
end
