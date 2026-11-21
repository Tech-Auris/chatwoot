class CreateVirtualClinicSummaries < ActiveRecord::Migration[7.1]
  def change
    # Which of Helena's summaries each person wants, and at what hour.
    create_table :virtual_clinic_summaries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :daily, null: false, default: false
      t.boolean :weekly, null: false, default: false
      t.boolean :monthly, null: false, default: false
      t.integer :hour, null: false, default: 8
      t.timestamps
    end
    add_index :virtual_clinic_summaries, %i[account_id user_id], unique: true

    # An alert for one person only (their summary); nil is for the whole team.
    add_reference :virtual_clinic_alerts, :user, foreign_key: { on_delete: :cascade }
  end
end
