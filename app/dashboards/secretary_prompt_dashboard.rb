require 'administrate/base_dashboard'

class SecretaryPromptDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    core_behavior: LongTextField,
    communication_rules: LongTextField,
    medical_compliance: LongTextField,
    tools_usage: LongTextField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id core_behavior updated_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id core_behavior communication_rules medical_compliance tools_usage created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[core_behavior communication_rules medical_compliance tools_usage].freeze

  def display_resource(prompt)
    "Secretary prompt ##{prompt.id}"
  end
end
