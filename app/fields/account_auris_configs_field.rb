require 'administrate/field/base'

# The account's n8n settings (see AurisConfig) on the Super Admin account page:
# every key with the value the account gets, its own or the default, plus a
# link to edit or add the account's value.
class AccountAurisConfigsField < Administrate::Field::Base
  def rows
    values = data.index_by(&:auris_config_id)
    AurisConfig.order(:id).map { |config| [config, values[config.id]] }
  end
end
