class AddTermsAcceptanceCampaignSchema < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    # The "Última atualização" stamp of the marketing page — the date that
    # names the version in front of the manager who signs it.
    add_column :terms_versions, :document_date, :date

    create_table :terms_acceptance_requests do |t|
      t.references :terms_version, null: false, foreign_key: true
      # A SuperAdmin is an STI subclass of User; the FK lives on `users`.
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      # `signature` is reserved for the sales-checkout flow; the super admin
      # wizard only produces `update` campaigns.
      t.integer :kind, null: false, default: 1
      t.integer :status, null: false, default: 0

      t.date :document_date, null: false
      t.datetime :deadline_at, null: false

      t.timestamps
    end

    add_index :terms_acceptance_requests, :status
    add_index :terms_acceptance_requests, :deadline_at

    change_table :terms_acceptances, bulk: true do |t|
      t.references :terms_acceptance_request, foreign_key: true
      t.references :account_user, foreign_key: true
      # Backfilled to :signature on legacy rows below; nullable stays out —
      # every future row is either :signature (sales) or :update (campaign).
      t.integer :kind
      t.datetime :deadline_at
      # A campaign marks a subset of the account managers as required signers;
      # the flag lets the report answer "is this account done?" without a join.
      t.boolean :required, default: false, null: false
    end

    add_index :terms_acceptances, :kind
    add_index :terms_acceptances, :deadline_at

    # Lets an OperationsNotification carry a domain object (a
    # TermsAcceptanceRequest today) so the frontend can swap the modal body
    # without a new endpoint.
    change_table :operations_notifications, bulk: true do |t|
      t.references :subject, polymorphic: true, index: true
    end
  end
end
