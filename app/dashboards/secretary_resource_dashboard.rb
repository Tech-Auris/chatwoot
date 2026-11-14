require 'administrate/base_dashboard'

class SecretaryResourceDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    secretary_resource_type: Field::BelongsTo.with_options(searchable: false),
    key: Field::String.with_options(searchable: true),
    idioma: Field::String,
    resource_url: Field::Url,
    caption: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account key idioma secretary_resource_type].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account key idioma secretary_resource_type resource_url caption created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account key idioma secretary_resource_type resource_url caption].freeze

  # Search `account:<id>` to list one account's resources.
  COLLECTION_FILTERS = {
    account: ->(resources, account_id) { resources.where(account_id: account_id) }
  }.freeze

  def display_resource(secretary_resource)
    [secretary_resource.key, secretary_resource.idioma].compact.join(' · ')
  end
end
