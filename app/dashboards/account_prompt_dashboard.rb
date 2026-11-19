require 'administrate/base_dashboard'

class AccountPromptDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    name: Field::String,
    inbox_ids: InboxIdsField,
    ai_prompt_system_message: LongTextField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account name inbox_ids].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account name inbox_ids ai_prompt_system_message created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account name inbox_ids ai_prompt_system_message].freeze

  # Search `account:<id>` to list one account's prompts.
  COLLECTION_FILTERS = {
    account: ->(prompts, account_id) { prompts.where(account_id: account_id) }
  }.freeze

  def display_resource(prompt)
    "#{prompt.account&.name} · #{prompt.name}"
  end
end
