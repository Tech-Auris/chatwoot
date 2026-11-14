# The Início page looks up, lead by lead, whether the AI user wrote in it.
# Production already has this index (created by hand), hence `if_not_exists`.
class AddAccountSenderConversationIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :messages, [:account_id, :sender_type, :sender_id, :conversation_id],
              name: 'idx_messages_account_sender_senderid_conversation', algorithm: :concurrently, if_not_exists: true
  end
end
