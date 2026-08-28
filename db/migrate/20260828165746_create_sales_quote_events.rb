class CreateSalesQuoteEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_quote_events do |t|
      t.references :sales_quote, null: false, foreign_key: true
      # Null when the prospect acted: the public pages have no user behind them.
      t.references :user, foreign_key: true

      t.string :event, null: false
      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :sales_quote_events, [:sales_quote_id, :created_at]
  end
end
