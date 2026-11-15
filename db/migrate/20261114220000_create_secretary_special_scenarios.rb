class CreateSecretarySpecialScenarios < ActiveRecord::Migration[7.1]
  def change
    create_table :secretary_special_scenarios do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.text :situacao
      t.text :gatilho
      t.text :instrucao
      t.timestamps
    end
    add_index :secretary_special_scenarios, [:account_id, :name]
  end
end
