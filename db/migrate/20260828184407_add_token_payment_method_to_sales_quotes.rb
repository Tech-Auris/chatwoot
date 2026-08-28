class AddTokenPaymentMethodToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    # Card saved for the token charges. It may be the same one that paid the
    # subscription or a different one — the customer chooses.
    add_column :sales_quotes, :token_payment_method_id, :string
  end
end
