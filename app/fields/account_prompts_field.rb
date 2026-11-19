require 'administrate/field/base'

# The account's prompts on the Super Admin account page, the general one first,
# each with a link to edit it, plus a link to add one for this account.
class AccountPromptsField < Administrate::Field::Base
  def prompts
    data.ordered
  end
end
