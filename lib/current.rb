module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # Set to true while ingesting backfilled WhatsApp messages via the Baileys
  # history-sync flow. Models check this to suppress live-only side effects
  # (event dispatch, automation, notifications, outbound webhooks, read
  # receipts) that would either spam users or fire incorrectly for messages
  # that are days/weeks old.
  thread_mattr_accessor :history_import
  # Why the AI is being turned off (:contact, :contact_manual, :inbox or
  # :schedule), set by Conversations::AiAutoOffService and
  # Contact#disable_ai!, so the activity names the reason instead of the
  # generic "AI turned off".
  thread_mattr_accessor :ai_off_reason
  # Who and where a change came from, for the activity log (ActivityLog):
  # the origin (dashboard, api, job, super_admin, login), the request IP and
  # id, and the super admin acting from the console.
  thread_mattr_accessor :audit_source
  thread_mattr_accessor :audit_ip
  thread_mattr_accessor :audit_request_id
  thread_mattr_accessor :audit_actor

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.history_import = nil
    Current.ai_off_reason = nil
    Current.audit_source = nil
    Current.audit_ip = nil
    Current.audit_request_id = nil
    Current.audit_actor = nil
  end
end
