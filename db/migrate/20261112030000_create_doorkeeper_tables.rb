# OAuth 2.1 for the Auris MCP: claude.ai / ChatGPT register themselves as
# public clients (PKCE, no secret), the clinic owner or manager authorizes on
# the dashboard, and the issued tokens read the API on their behalf.
class CreateDoorkeeperTables < ActiveRecord::Migration[7.1]
  def change
    create_applications
    create_access_grants
    create_access_tokens
  end

  private

  def create_applications
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.boolean :confidential, null: false, default: false
      t.timestamps
    end
    add_index :oauth_applications, :uid, unique: true
  end

  def create_access_grants
    create_table :oauth_access_grants do |t|
      t.references :resource_owner, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ''
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_grants, :token, unique: true
  end

  def create_access_tokens
    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.string :previous_refresh_token, null: false, default: ''
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
