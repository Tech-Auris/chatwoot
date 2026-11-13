class RemoveAdministratorsFromInboxMembers < ActiveRecord::Migration[7.1]
  # Administrators (the Auris team) are no longer inbox collaborators, except the AI user.
  def up
    ai_user_id = GlobalConfigService.load('SECRETARY_AI_USER_ID', nil).to_i

    InboxMember.joins(inbox: { account: :account_users })
               .where('account_users.user_id = inbox_members.user_id')
               .where(account_users: { role: AccountUser.roles[:administrator] })
               .where.not(user_id: ai_user_id)
               .find_each(&:destroy)
  end

  def down; end
end
