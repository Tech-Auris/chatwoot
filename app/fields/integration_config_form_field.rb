require 'administrate/field/base'

# The integration form: one input per field of the ERP (`erp_sources.fields`).
# The account and the ERP come from the link that opened it and don't change.
class IntegrationConfigFormField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    [:account_id, :erp_source_id, { attr => {} }]
  end

  def fields
    resource.erp_source&.fields || []
  end

  def value(field)
    value = resource.config[field['key']]
    field['type'] == 'json' && !value.nil? ? JSON.pretty_generate(value) : value
  end

  def secret_hint(field)
    masked = resource.masked_config[field['key']]
    masked.present? ? "#{masked} saved; leave blank to keep it" : nil
  end
end
