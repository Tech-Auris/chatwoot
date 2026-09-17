class CreateMarketingIntegrations < ActiveRecord::Migration[7.1]
  # Per-account credentials for the two providers the clinic can push
  # conversions to: Meta CAPI (pixel + access_token + optional test_event_code)
  # and Google Ads Enhanced Conversions (customer_id + oauth_token +
  # conversion_id). `credentials` is jsonb because the payload shape differs
  # per provider and the ActiveRecord `encrypts` helper covers a single string
  # column at a time — we serialize the hash to JSON and encrypt the whole
  # `credentials_ciphertext` column at the model level.
  #
  # One row per (account, provider) — no clinic ships two Meta CAPI setups on
  # the same account. Status controls whether the dispatcher acts on this
  # integration.
  def change
    create_table :marketing_integrations do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.integer :provider, null: false
      t.integer :status, null: false, default: 0
      t.text :credentials_ciphertext
      t.timestamps
    end

    add_index :marketing_integrations, %i[account_id provider], unique: true, name: 'index_marketing_integrations_on_account_and_provider'
    add_index :marketing_integrations, :status
  end
end
