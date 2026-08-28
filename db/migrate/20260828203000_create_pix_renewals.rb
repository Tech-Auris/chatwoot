class CreatePixRenewals < ActiveRecord::Migration[7.1]
  def change
    create_table :pix_renewals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sales_quote, null: false, foreign_key: true

      # The period this payment covers. Only the due date is kept: PIX is
      # charged once per cycle, and the month it falls in is what the team
      # looks for.
      t.date :due_on, null: false
      t.integer :amount, null: false
      t.integer :status, null: false, default: 0

      t.string :stripe_invoice_id
      t.string :hosted_invoice_url
      t.string :paid_via
      t.datetime :paid_at

      t.timestamps
    end

    # The alert reads "what is due soon and not settled", which is this index.
    add_index :pix_renewals, [:status, :due_on]
  end
end
