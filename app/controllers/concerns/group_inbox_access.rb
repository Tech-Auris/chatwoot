# WhatsApp group actions (leave, settings, members, invites, join requests,
# sync) act on the group through the inbox it lives on. Contacts are shared
# across the account, so authorizing the contact alone let an agent act on
# groups of inboxes they can't open; this also requires access to that inbox
# (administrators and managers have every inbox).
module GroupInboxAccess
  extend ActiveSupport::Concern

  included do
    before_action :ensure_group_inbox_access
  end

  private

  def ensure_group_inbox_access
    return if group_inbox_accessible?

    render json: { error: 'You do not have access to the inbox of this group' }, status: :unauthorized
  end

  # A contact not tied to any inbox has no WhatsApp session to act through.
  def group_inbox_accessible?
    inbox = @contact.contact_inboxes.first&.inbox
    inbox.nil? || Current.user.assigned_inboxes.exists?(inbox.id)
  end
end
