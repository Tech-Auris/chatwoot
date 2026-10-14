require 'administrate/base_dashboard'

class AiModelDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    ai_provider: Field::BelongsTo,
    name: Field::String,
    key: Field::String.with_options(searchable: true),
    model_id: Field::String,
    status: Field::Select.with_options(searchable: false, collection: ->(_field) { AiModel.statuses.keys }),
    account_secretaries: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id ai_provider name key model_id status].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id ai_provider name key model_id status created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[ai_provider name key model_id status].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(ai_model)
    "#{ai_model.ai_provider.name} · #{ai_model.name}"
  end
end
