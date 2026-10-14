require 'administrate/base_dashboard'

class AccountStatusDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    status: Field::String,
    label: Field::String,
    name: Field::String,
    send_private_message: Field::Boolean,
    private_message: Field::Text,
    message_cooldown_minutes: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[label name send_private_message message_cooldown_minutes].freeze

  SHOW_PAGE_ATTRIBUTES = %i[label status name send_private_message private_message message_cooldown_minutes updated_at].freeze

  # `status` and `name` are what the code and the n8n secretary key on, so
  # only the wording and the note can change here.
  FORM_ATTRIBUTES = %i[label send_private_message private_message message_cooldown_minutes].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(account_status)
    account_status.label
  end
end
