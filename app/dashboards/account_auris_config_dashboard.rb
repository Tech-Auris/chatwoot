require 'administrate/base_dashboard'

class AccountAurisConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    auris_config: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['config_key']),
    value: Field::Text.with_options(searchable: true),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account auris_config value].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account auris_config value created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account auris_config value].freeze

  # Search `account:<id>` to list one account's values.
  COLLECTION_FILTERS = {
    account: ->(values, account_id) { values.where(account_id: account_id) }
  }.freeze

  def display_resource(value)
    "#{value.account&.name} · #{value.auris_config&.config_key}"
  end
end
