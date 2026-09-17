class BackfillConversationOrigemFromContact < ActiveRecord::Migration[7.1]
  # Copies the current Contact.additional_attributes['origem'] to every
  # existing conversation of that contact. Applies the same value to all past
  # conversations for the contact — we can't reconstruct per-conversation
  # attribution retroactively, and matching Contact.origem preserves what the
  # sidebar was showing before the migration.
  #
  # Idempotent: only writes conversations whose origem column is still NULL,
  # so replaying is safe. Skips rows the OPTIONS list wouldn't accept (dev
  # data or one-off manual writes) — those stay NULL and the operator can
  # backfill via the dropdown.
  ORIGEM_OPTIONS = [
    'Evento',
    'Facebook',
    'Google',
    'Indicação de cliente',
    'Indicação de colega',
    'Influenciador',
    'Instagram',
    'Orgânico'
  ].freeze
  BATCH_SIZE = 500

  disable_ddl_transaction!

  def up
    scope = execute(<<~SQL.squish)
      SELECT id, additional_attributes->>'origem' AS origem
      FROM contacts
      WHERE additional_attributes ? 'origem'
        AND additional_attributes->>'origem' <> ''
    SQL

    scope.to_a.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        origem = row['origem']
        next unless ORIGEM_OPTIONS.include?(origem)

        execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, origem, row['id']]))
          UPDATE conversations SET origem = ? WHERE contact_id = ? AND origem IS NULL
        SQL
      end
    end
  end

  def down
    # Kept nullable in this PR, so a rollback just clears the backfilled values.
    execute('UPDATE conversations SET origem = NULL WHERE origem IS NOT NULL')
  end
end
