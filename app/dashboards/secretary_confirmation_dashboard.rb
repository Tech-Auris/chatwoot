require 'administrate/base_dashboard'

class SecretaryConfirmationDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    versao_workflow: Field::String,
    calendar_id: Field::String,
    inbox_id: Field::String,
    unidade_id: Field::Number,
    message_96h: Field::Text,
    message_72h: Field::Text,
    message_48h: Field::Text,
    message: Field::Text,
    message_hj: Field::Text,
    message_2h: Field::Text,
    message_30m: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account versao_workflow calendar_id inbox_id unidade_id].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id account versao_workflow calendar_id inbox_id unidade_id
                            message_96h message_72h message_48h message message_hj message_2h message_30m created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[account versao_workflow calendar_id inbox_id unidade_id
                       message_96h message_72h message_48h message message_hj message_2h message_30m].freeze

  # Search `account:<id>` to list one account's reminder settings.
  COLLECTION_FILTERS = {
    account: ->(confirmations, account_id) { confirmations.where(account_id: account_id) }
  }.freeze

  def display_resource(confirmation)
    "#{confirmation.account&.name} · v#{confirmation.versao_workflow.presence || '2'}"
  end
end
