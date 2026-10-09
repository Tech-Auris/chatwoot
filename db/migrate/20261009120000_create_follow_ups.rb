# One row per follow-up (FUP) the n8n workflow sends on a conversation, so
# the team can see how many went out, when, and whether the patient came back.
class CreateFollowUps < ActiveRecord::Migration[7.1]
  def change
    create_table :follow_ups do |t|
      t.references :account, null: false, index: false
      t.references :conversation, null: false, index: false
      t.references :inbox, null: false
      t.references :message, index: false
      t.string :run_id, null: false
      t.integer :step, null: false
      t.integer :delay_minutes, null: false
      t.integer :delivery_status, null: false, default: 0
      t.integer :outcome, null: false, default: 0
      t.text :error_message
      t.datetime :processed_at
      t.datetime :outcome_at
      t.timestamps
    end

    add_index :follow_ups, [:account_id, :created_at]
    add_index :follow_ups, [:conversation_id, :run_id, :step], unique: true
  end
end
