class CreateLoginEvents < ActiveRecord::Migration[7.1]
  # Per-account audit trail of every successful login. One row per
  # (login, account) so filtering "quem entrou nessa conta?" is a plain
  # indexed lookup. Users with no account membership at login time still
  # get a single row with `account_id` and `role` null so the trail is
  # never lost.
  def change
    create_table :login_events do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :account, foreign_key: true, index: false
      # Mirrors AccountUser.role: { agent: 0, administrator: 1, manager: 2 }.
      # Snapshot of the user's role in this account at the moment of login.
      t.integer :role
      t.string :ip_address
      t.string :user_agent
      t.string :browser_name
      t.string :browser_version
      t.string :platform_name
      t.string :platform_version
      t.string :device_name
      t.string :city
      t.string :country
      t.string :country_code
      t.timestamps
    end

    add_index :login_events, [:account_id, :created_at], order: { created_at: :desc }
    add_index :login_events, [:user_id, :created_at], order: { created_at: :desc }
  end
end
