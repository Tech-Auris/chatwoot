class CreateSalesAsaasInstallmentPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_asaas_installment_payments do |t|
      t.references :sales_quote, null: false, foreign_key: true, index: true
      t.string :asaas_payment_id, null: false
      t.string :asaas_installment_id, null: false
      t.integer :installment_number
      t.integer :amount_cents, null: false, default: 0
      # 0=pending, 1=received, 2=confirmed, 3=overdue, 4=refunded, 5=deleted.
      # Mirrors the AsaaS payment lifecycle we care about; other statuses
      # (awaiting_risk_analysis, etc.) collapse to :pending.
      t.integer :status, null: false, default: 0
      t.date :due_date
      t.datetime :paid_at
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :sales_asaas_installment_payments, :asaas_payment_id, unique: true
    add_index :sales_asaas_installment_payments, :asaas_installment_id
  end
end
