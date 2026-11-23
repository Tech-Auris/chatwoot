# Summaries now come from Helena or from Luciano (marketing): one choice per
# person and teammate. Existing rows are Helena's (manager = 1).
class AddPersonaToVirtualClinicSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :virtual_clinic_summaries, :persona, :integer, null: false, default: 1
    remove_index :virtual_clinic_summaries, %i[account_id user_id], unique: true
    add_index :virtual_clinic_summaries, %i[account_id user_id persona], unique: true, name: 'index_virtual_clinic_summaries_on_account_user_persona'
  end
end
