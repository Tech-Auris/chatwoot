# The Supabase `confirmacoes_send_log` table: one row per reminder already sent.
class CreateSecretaryConfirmationSendLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :secretary_confirmation_send_logs do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :account, null: false, foreign_key: true, index: false
      t.text :calendar_id, null: false, default: ''
      t.text :event_id, null: false
      t.string :reminder_type, null: false
      t.datetime :sent_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.index [:account_id, :event_id, :calendar_id, :reminder_type], unique: true, name: 'index_secretary_confirmation_send_logs_uniqueness'
    end
  end
end
