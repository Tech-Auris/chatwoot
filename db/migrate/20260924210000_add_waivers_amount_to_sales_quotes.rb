# Stores the sum of the item-targeted discounts that ran in the calculator
# (api_integration waiver + scoped-coupon waiver). We need it broken out
# from `discount_amount` so the ClickUp CRM sync can compute the value of
# the implementation line: the sales team wants it as
# `impl_subtotal - waivers_amount`, i.e., the effective implementation
# price the customer actually paid for.
class AddWaiversAmountToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_quotes, :waivers_amount, :integer, default: 0, null: false
  end
end
