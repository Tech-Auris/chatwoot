class AddBillingNameToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    # Legal name of the company the invoice goes to, when the customer wants it
    # issued against a CNPJ. Kept apart from `company_name`, which is the clinic
    # the account is named after — they are frequently different.
    add_column :sales_quotes, :billing_name, :string
  end
end
