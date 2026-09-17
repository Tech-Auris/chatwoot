class NullifyContactOrigem < ActiveRecord::Migration[7.1]
  # Removes the legacy `origem` key from `contacts.additional_attributes`.
  # The value has been migrated to `conversations.origem` (see
  # 20260916230001_backfill_conversation_origem_from_contact.rb) and every
  # reader now goes through the conversation column, so keeping the contact
  # copy just risks confusion in a future PR that scans for it.
  #
  # In batches; disabled DDL wrap because the update loops through a large
  # scope on production accounts.
  BATCH_SIZE = 1_000

  disable_ddl_transaction!

  def up
    loop do
      updated = execute(<<~SQL.squish).cmd_tuples
        UPDATE contacts SET additional_attributes = additional_attributes - 'origem'
        WHERE id IN (
          SELECT id FROM contacts
          WHERE additional_attributes ? 'origem'
          LIMIT #{BATCH_SIZE}
        )
      SQL
      break if updated.zero?
    end
  end

  def down
    # Not reversible — `conversations.origem` remains the source of truth.
    # A rollback of this migration alone would leave the two out of sync.
  end
end
