class AddAsaasInstallmentFieldsToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    change_table :sales_quotes, bulk: true do |t|
      t.string :asaas_customer_id
      t.string :asaas_installment_id
      t.string :asaas_invoice_url
    end
  end
end
