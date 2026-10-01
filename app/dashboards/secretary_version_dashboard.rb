require 'administrate/base_dashboard'

class SecretaryVersionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    nickname: Field::String,
    released_at: Field::DateTime,
    webhook_url: Field::String,
    workflow_id: Field::String,
    status: Field::Select.with_options(searchable: false, collection: ->(_field) { SecretaryVersion.statuses.keys }),
    account_secretaries: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    nickname
    status
    released_at
    webhook_url
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    nickname
    status
    released_at
    webhook_url
    workflow_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    nickname
    status
    released_at
    webhook_url
    workflow_id
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(secretary_version)
    secretary_version.name
  end
end
