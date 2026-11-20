require 'administrate/base_dashboard'

class AccountIntegrationDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    erp_source: Field::BelongsTo.with_options(order: :id),
    config: IntegrationConfigField,
    config_json: LongTextField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account erp_source config].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account erp_source config created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account erp_source config_json].freeze

  # Search `account:<id>` to list one account's integrations.
  COLLECTION_FILTERS = {
    account: ->(integrations, account_id) { integrations.where(account_id: account_id) }
  }.freeze

  def display_resource(integration)
    "#{integration.account&.name} · #{integration.erp_source&.name}"
  end
end
