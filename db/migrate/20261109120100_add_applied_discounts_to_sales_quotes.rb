class AddAppliedDiscountsToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_quotes, :applied_discounts, :jsonb, null: false, default: []
  end
end
