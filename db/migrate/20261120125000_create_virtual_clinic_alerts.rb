# When something needs the clinic owner (patients waiting, a silent inbox,
# conversion dropping…), an AI teammate "raises her hand" in the Clínica
# virtual. Each alert is a fixed rule that fired, with the numbers behind it.
class CreateVirtualClinicAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :virtual_clinic_alerts do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.integer :persona, null: false
      t.string :rule, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :acknowledged_at
      t.timestamps
    end
    add_index :virtual_clinic_alerts, %i[account_id rule created_at]
  end
end
