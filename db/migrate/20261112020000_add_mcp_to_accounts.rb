# The Auris MCP (AI assistants reading the account through the API) is off
# until an administrator turns it on and accepts the data-sharing term; who
# accepted it and when is kept on the account.
class AddMcpToAccounts < ActiveRecord::Migration[7.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.boolean :mcp_enabled, default: false, null: false
      t.datetime :mcp_enabled_at
      t.references :mcp_enabled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
    end
  end
end
