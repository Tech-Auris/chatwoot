# Conversations between a clinic user and an AI teammate of the Clínica
# virtual. One open thread per user and persona; "Nova conversa" starts
# another and keeps the old one for audit. Tool results are not stored:
# they carry patient data and the answer already summarizes them.
class CreateVirtualClinicConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :virtual_clinic_threads do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :persona, null: false
      t.timestamps
    end
    add_index :virtual_clinic_threads, %i[account_id user_id persona created_at], name: 'index_vc_threads_on_owner_and_persona'

    create_table :virtual_clinic_messages do |t|
      t.references :thread, null: false, foreign_key: { to_table: :virtual_clinic_threads }
      t.integer :role, null: false
      t.integer :status, null: false, default: 0
      t.text :content
      t.jsonb :tool_calls, null: false, default: []
      t.string :model
      t.integer :input_tokens
      t.integer :output_tokens
      t.timestamps
    end
  end
end
