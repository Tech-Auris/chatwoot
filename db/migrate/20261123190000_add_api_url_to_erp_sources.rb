# The base URL of an ERP's API, for what Rails calls on it directly (ERP →
# Agenda). Filled in on the ERP in Super Admin; blank while nothing needs it.
class AddApiUrlToErpSources < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_sources, :api_url, :string
  end
end
