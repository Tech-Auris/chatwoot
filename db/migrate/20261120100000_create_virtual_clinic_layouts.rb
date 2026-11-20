# The Clínica virtual as each clinic arranged it in the editor: floor and
# wall art, furniture, room names and the AI team (name, look and seat). Only
# what the editor changes is stored; the rest comes from the default clinic.
class CreateVirtualClinicLayouts < ActiveRecord::Migration[7.1]
  def change
    create_table :virtual_clinic_layouts do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.jsonb :layout, null: false, default: {}
      t.timestamps
    end
  end
end
