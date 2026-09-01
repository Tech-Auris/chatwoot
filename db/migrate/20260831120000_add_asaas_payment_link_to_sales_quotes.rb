class AddAsaasPaymentLinkToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    # The link the customer was sent to, kept so a payment can be traced back
    # to the proposal it belongs to when the team reconciles AsaaS.
    add_column :sales_quotes, :asaas_payment_link_id, :string
    add_column :sales_quotes, :asaas_payment_link_url, :string
  end
end
