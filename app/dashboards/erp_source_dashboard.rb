require 'administrate/base_dashboard'

# The id is typed in on creation (the one the ERP has in the Supabase
# `integration_type` table) and can't change afterwards. `api_url` is the base
# URL of the ERP's API for what Rails calls on it directly (ERP → Agenda).
class ErpSourceDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    active: Field::Boolean,
    api_url: Field::String.with_options(searchable: false),
    fields: ErpFieldsField,
    accounts: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name active accounts].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id name active api_url fields accounts created_at updated_at].freeze

  FORM_ATTRIBUTES_NEW = %i[id name active api_url fields].freeze
  FORM_ATTRIBUTES_EDIT = %i[name active api_url fields].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(erp_source)
    erp_source.name
  end
end
