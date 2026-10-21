require 'administrate/base_dashboard'

class AiProviderDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    key: Field::String,
    ai_models: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name key ai_models].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id name key ai_models created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[name key].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(ai_provider)
    ai_provider.name
  end
end
