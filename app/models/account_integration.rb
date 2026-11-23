# The credentials an account uses to reach its ERP (or calendar), moved from the
# Supabase `integration_<erp>` tables and edited in Super Admin. `config` keeps
# that table's columns under the same names (Klingo's `app-token` included), so
# the n8n nodes that replaced the Supabase ones return the same keys. Which keys
# an ERP has, their types and which are secret come from `erp_sources.fields`.
#
# An account may keep rows for several ERPs; the one that counts is the row of
# the account's `erp_source`. n8n reads it live from Postgres on every call:
#
#   select x.* from account_integrations ai,
#     jsonb_to_record(ai.config) as x(access_token text, local_id bigint, ...)
#   where ai.account_id = $1 and ai.erp_source_id = 2
#
# Plain text, as in Supabase today; encryption comes with the V2 story.
class AccountIntegration < ApplicationRecord
  include Auditable

  belongs_to :account
  belongs_to :erp_source

  validates :erp_source_id, uniqueness: { scope: :account_id }
  validate :config_values_are_valid

  before_validation :apply_config_values, if: -> { @config_values }

  # Secret values never reach the change history, only the fact that `config` changed.
  auditable filtered: %i[config], label: ->(integration) { integration.erp_source&.name }

  # A form value cast to the field's type, as [value, error]. Blank is nil.
  def self.cast(field, value)
    return [value, nil] unless value.is_a?(String)
    return [nil, nil] if value.strip.empty?

    case field['type']
    when 'number' then Integer(value.strip, 10, exception: false).then { |number| number ? [number, nil] : [nil, 'precisa ser um número inteiro'] }
    when 'json' then [JSON.parse(value), nil]
    else [value, nil]
    end
  rescue JSON::ParserError
    [nil, 'não é um JSON válido']
  end

  # The Super Admin form posts one value per field of the ERP. A blank secret
  # keeps the saved one; keys the ERP no longer lists are kept as they are.
  def config_values
    config
  end

  def config_values=(values)
    @config_values = values.to_h.stringify_keys
  end

  # `config` with each secret cut down to its first 3 and last 4 characters (`abc••••1234`).
  def masked_config
    secrets = erp_source&.secret_keys || []
    config.to_h { |key, value| [key, secrets.include?(key) && value.present? ? mask(value) : value] }
  end

  def active?
    account.erp_source_id == erp_source_id
  end

  private

  def apply_config_values
    @config_errors = []
    self.config = (erp_source&.fields || []).each_with_object(config.dup) { |field, config| apply_config_value(field, config) }
    @config_values = nil
  end

  def apply_config_value(field, config)
    key = field['key']
    return unless @config_values.key?(key)
    return if field['secret'] && @config_values[key].blank? && config[key].present?

    value, error = self.class.cast(field, @config_values[key])
    error ? @config_errors << "#{field['label']} #{error}" : config[key] = value
  end

  def config_values_are_valid
    @config_errors&.each { |error| errors.add(:config, error) }
  end

  def mask(value)
    value.is_a?(String) && value.length > 10 ? "#{value.first(3)}••••#{value.last(4)}" : '••••'
  end
end
