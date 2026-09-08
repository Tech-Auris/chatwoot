class AddApiIntegrationWaivedToSalesQuotes < ActiveRecord::Migration[7.1]
  # The seller can waive the "Integração via API" line during the meeting;
  # the flag lives on the quote so the discount rides along with what was
  # frozen on the proposal, no need to re-derive from the item list.
  def change
    add_column :sales_quotes, :api_integration_waived, :boolean, default: false, null: false
  end
end
