# A reminder the n8n confirmation flows already sent, so it isn't sent twice.
# Moved from the Supabase `confirmacoes_send_log` table; the unique index on
# account + event + calendar + reminder type is what dedupes.
class SecretaryConfirmationSendLog < ApplicationRecord
  belongs_to :account

  validates :event_id, :reminder_type, presence: true

  # Logs the reminder unless it's already there, atomically: true when this call
  # logged it, false when it had already been sent.
  def self.reserve(account:, event_id:, reminder_type:, calendar_id: nil)
    inserted = insert_all( # rubocop:disable Rails/SkipsModelValidations
      [{ account_id: account.id, event_id: event_id.to_s, reminder_type: reminder_type, calendar_id: calendar_id.to_s }],
      unique_by: :index_secretary_confirmation_send_logs_uniqueness
    )
    inserted.rows.any?
  end
end
