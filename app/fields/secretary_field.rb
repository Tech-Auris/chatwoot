require 'administrate/field/base'

# "Secretária" block of the Super Admin account form: version, inboxes,
# Simulador version and signing secret. Rendered by the AccountSecretary Vue
# component and saved by AccountsController#update.
class SecretaryField < Administrate::Field::Base
  def to_s
    data&.secretary_version&.name.to_s
  end
end
