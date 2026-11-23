require 'administrate/field/base'

# An integration's `config` with the secrets masked (`abc••••1234`).
class IntegrationConfigField < Administrate::Field::Base
  def entries
    resource.masked_config
  end
end
