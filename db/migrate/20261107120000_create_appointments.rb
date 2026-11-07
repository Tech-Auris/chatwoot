class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_appointments
    create_appointment_procedures
  end

  private

  def create_appointments
    create_table :appointments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :erp_source, foreign_key: true
      t.string :external_id
      t.datetime :scheduled_for
      t.string :professional_external_id
      t.string :professional_name
      t.string :procedure_external_id
      t.string :procedure_name
      t.integer :status, null: false, default: 0
      t.datetime :attended_at
      t.timestamps
    end
    add_index :appointments, [:account_id, :erp_source_id, :external_id], unique: true, name: 'index_appointments_on_account_source_external'
    add_index :appointments, [:account_id, :scheduled_for]
  end

  def create_appointment_procedures
    create_table :appointment_procedures do |t|
      t.references :appointment, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :procedure_external_id
      t.string :procedure_name
      t.integer :amount_paid_cents
      t.timestamps
    end
  end
end
