class CreateTermsVersionsAndAcceptances < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :terms_versions do |t|
      t.string :source_url, null: false
      # The terms as they read at the moment of signing. Pointing at a live URL
      # would let the contract change under a signature already given.
      t.text :content, null: false
      t.string :content_hash, null: false
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :terms_versions, :content_hash

    create_table :terms_acceptances do |t|
      t.references :terms_version, null: false, foreign_key: true
      # A signature comes either from a sale or from a re-signature asked of an
      # existing account, so both sides are optional.
      t.references :sales_quote, foreign_key: true
      t.references :account, foreign_key: true

      t.integer :status, null: false, default: 0
      t.string :request_token
      t.datetime :requested_at

      t.string :signer_name
      t.string :signer_email
      t.string :signer_document
      t.datetime :signed_at
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :terms_acceptances, :request_token, unique: true
    add_index :terms_acceptances, :status
  end
end
