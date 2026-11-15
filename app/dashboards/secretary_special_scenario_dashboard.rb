require 'administrate/base_dashboard'

class SecretarySpecialScenarioDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    name: Field::String.with_options(searchable: true),
    situacao: Field::Text,
    gatilho: Field::Text,
    instrucao: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account name situacao].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account name situacao gatilho instrucao created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account name situacao gatilho instrucao].freeze

  # Search `account:<id>` to list one account's scenarios.
  COLLECTION_FILTERS = {
    account: ->(scenarios, account_id) { scenarios.where(account_id: account_id) }
  }.freeze

  def display_resource(scenario)
    scenario.name
  end
end
