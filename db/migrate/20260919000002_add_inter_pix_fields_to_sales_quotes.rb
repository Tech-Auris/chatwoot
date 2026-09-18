class AddInterPixFieldsToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    change_table :sales_quotes, bulk: true do |t|
      t.string :inter_txid
      t.text :inter_pix_payload
    end

    add_index :sales_quotes, :inter_txid, unique: true, where: 'inter_txid IS NOT NULL'
  end
end
