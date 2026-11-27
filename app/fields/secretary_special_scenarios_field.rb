require 'administrate/field/base'

# The account's special scenarios on the Super Admin account page, each with a
# link to edit it, plus a link to add one for this account.
class SecretarySpecialScenariosField < Administrate::Field::Base
  def scenarios
    data.order(:name)
  end
end
