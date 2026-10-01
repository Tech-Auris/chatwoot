class CreateSecretaryVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :secretary_versions do |t|
      t.string :name, null: false
      t.string :nickname
      t.datetime :released_at
      t.string :webhook_url, null: false
      t.string :workflow_id
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :secretary_versions, :name, unique: true
    add_index :secretary_versions, :webhook_url, unique: true

    create_table :account_secretaries do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :secretary_version, foreign_key: true
      t.references :simulator_version, foreign_key: { to_table: :secretary_versions }
      t.string :secret
      t.timestamps
    end

    add_column :inboxes, :secretary_enabled, :boolean, null: false, default: false
  end
end
