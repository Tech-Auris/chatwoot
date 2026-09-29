# Media Hub: every role browses the attachments of the inboxes it can see;
# only administrators and managers delete them — the delete is permanent
# (the message and its file are destroyed, not flagged), including media the
# customer sent.
class MediaHubPolicy < ApplicationPolicy
  def destroy?
    @account_user.administrator? || @account_user.manager?
  end
end
