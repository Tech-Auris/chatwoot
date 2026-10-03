class CreateSalesContractTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_contract_templates do |t|
      t.integer :version, null: false
      t.text :content, null: false
      t.string :created_by_name
      t.timestamps
    end
    add_index :sales_contract_templates, :version, unique: true
  end
end
