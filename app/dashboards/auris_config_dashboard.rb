require 'administrate/base_dashboard'

class AurisConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    config_key: Field::String.with_options(searchable: true),
    value_type: Field::String,
    default_value: Field::Text,
    description: Field::Text.with_options(searchable: true),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id config_key value_type default_value].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id config_key value_type default_value description created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[config_key value_type default_value description].freeze

  def display_resource(config)
    config.config_key
  end
end
