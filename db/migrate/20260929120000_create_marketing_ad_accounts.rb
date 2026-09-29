# Meta ad accounts whose spend feeds the reports (Gasto / CPL / CPA / ROAS).
# One integration can pull several: a clinic's own accounts plus the ones
# other portfolios share with it. Each row keeps the outcome of its last sync
# so the settings grid can say which account is fine and which lost access.
class CreateMarketingAdAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :marketing_ad_accounts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :marketing_integration, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false
      t.string :name
      t.string :currency
      t.boolean :enabled, null: false, default: true
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error
      t.integer :last_rows_synced
      t.timestamps
    end
    add_index :marketing_ad_accounts, [:marketing_integration_id, :external_id],
              unique: true, name: 'index_marketing_ad_accounts_on_integration_and_external_id'
  end
end
