require 'administrate/base_dashboard'

# Only backs the type select on the resource form; the types aren't editable.
class SecretaryResourceTypeDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = { id: Field::Number, description: Field::String }.freeze
  COLLECTION_ATTRIBUTES = %i[id description].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id description].freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(type)
    "#{type.id} · #{type.description}"
  end
end
