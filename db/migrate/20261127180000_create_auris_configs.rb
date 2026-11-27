class CreateAurisConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :auris_configs do |t|
      t.string :config_key, null: false
      t.string :value_type, null: false
      t.text :default_value
      t.text :description
      t.timestamps
    end
    add_index :auris_configs, :config_key, unique: true

    create_table :account_auris_configs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :auris_config, null: false, foreign_key: true
      t.text :value
      t.timestamps
    end
    add_index :account_auris_configs, [:account_id, :auris_config_id], unique: true
  end
end
