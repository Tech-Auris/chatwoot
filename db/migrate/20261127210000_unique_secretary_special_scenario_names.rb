class UniqueSecretarySpecialScenarioNames < ActiveRecord::Migration[7.1]
  def change
    remove_index :secretary_special_scenarios, [:account_id, :name]
    add_index :secretary_special_scenarios, 'account_id, lower(name)', unique: true,
                                                                       name: 'index_secretary_special_scenarios_on_account_id_and_lower_name'
  end
end
