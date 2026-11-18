require 'administrate/field/base'

# The account's inbox prompts on the Super Admin account page, each with a link
# to edit it, plus a link to add one for this account.
class AccountInboxPromptsField < Administrate::Field::Base
  def prompts
    data.order(:id)
  end
end
