class CreateSalesQuotes < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :sales_quotes do |t|
      # Opaque handle of the public link. The prospect has no login, so this is
      # what identifies the proposal — never the id.
      t.string :public_token, null: false
      # Sent by the seller over WhatsApp along with the link. Kept readable so
      # the seller can resend it; the real barrier is the phone check below.
      t.string :access_code, null: false
      # Last four digits of the prospect's WhatsApp, asked before signing or
      # paying. A forwarded link rarely travels with the owner's own number.
      t.string :verification_phone_last4

      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.references :account, foreign_key: true

      # ClickUp is the source of truth for the deal; these are a local mirror
      # so the report does not call the API for every row.
      t.string :clickup_task_id, null: false
      t.string :clickup_status
      t.datetime :clickup_status_synced_at

      t.integer :status, null: false, default: 0
      t.datetime :reserved_until

      t.string :prospect_name
      t.string :prospect_email
      t.string :prospect_phone
      t.string :prospect_document
      t.string :company_name
      t.string :company_document

      t.boolean :meeting_discount, null: false, default: false
      t.string :coupon_id
      t.integer :payment_method
      t.integer :billing_cycle

      # Amounts in cents, frozen when the proposal is built: a price archived or
      # replaced in Stripe later must not change what the prospect was shown.
      t.integer :subtotal_amount, null: false, default: 0
      t.integer :discount_amount, null: false, default: 0
      t.integer :total_amount, null: false, default: 0
      t.string :currency, null: false, default: 'brl'
      # Human-readable breakdown ("10% venda + 5% PIX"), carried to the Stripe
      # invoice so the charge explains itself there too.
      t.string :discount_summary

      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :stripe_invoice_id

      t.timestamps
    end

    add_index :sales_quotes, :public_token, unique: true
    add_index :sales_quotes, :clickup_task_id
    add_index :sales_quotes, :status
  end
end
