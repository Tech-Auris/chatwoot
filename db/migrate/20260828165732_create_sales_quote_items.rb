class CreateSalesQuoteItems < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_quote_items do |t|
      t.references :sales_quote, null: false, foreign_key: true

      t.string :stripe_price_id, null: false
      t.string :stripe_product_id
      # Name and amount are copies, not references: a Stripe price is immutable
      # but can be archived and replaced, and the proposal has to keep showing
      # what the prospect agreed to.
      t.string :name, null: false
      t.integer :unit_amount, null: false
      t.integer :quantity, null: false, default: 1
      t.string :recurring_interval
      t.integer :kind, null: false, default: 0

      t.timestamps
    end
  end
end
