class CreateSalesContracts < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_contracts do |t|
      t.references :sales_quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :sales_contract_template, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :person_type, null: false
      t.jsonb :data, null: false, default: {}
      t.string :payment_method, null: false
      t.integer :installments
      t.string :autentique_document_id
      t.string :signing_url
      t.boolean :sandbox, null: false, default: false
      t.text :error_message
      t.datetime :auris_signed_at
      t.datetime :signed_at
      t.datetime :cancelled_at
      t.datetime :deadline_at
      t.timestamps
    end
    add_index :sales_contracts, :autentique_document_id, unique: true
  end
end
