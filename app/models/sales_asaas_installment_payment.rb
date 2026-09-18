# One row per AsaaS payment inside an instalment book: for a semiannual
# boleto sale that is six rows, twelve for annual. The webhook writes here
# every time AsaaS reports a status change on a payment, so the audit trail
# holds the full history of every parcel (paid, overdue, refunded) without
# the finance team having to poll AsaaS by hand.
# == Schema Information
#
# Table name: sales_asaas_installment_payments
#
#  id                   :bigint           not null, primary key
#  amount_cents         :integer          default(0), not null
#  due_date             :date
#  installment_number   :integer
#  paid_at              :datetime
#  payload              :jsonb            not null
#  status               :integer          default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  asaas_installment_id :string           not null
#  asaas_payment_id     :string           not null
#  sales_quote_id       :bigint           not null
#
# Indexes
#
#  index_sales_asaas_installment_payments_on_asaas_installment_id  (asaas_installment_id)
#  index_sales_asaas_installment_payments_on_asaas_payment_id      (asaas_payment_id) UNIQUE
#  index_sales_asaas_installment_payments_on_sales_quote_id        (sales_quote_id)
#
# Foreign Keys
#
#  fk_rails_...  (sales_quote_id => sales_quotes.id)
#
class SalesAsaasInstallmentPayment < ApplicationRecord
  belongs_to :sales_quote

  # Mirrors the AsaaS payment lifecycle we care about; other statuses
  # (`AWAITING_RISK_ANALYSIS`, `PENDING`, ...) collapse to :pending on entry.
  enum :status, { pending: 0, received: 1, confirmed: 2, overdue: 3, refunded: 4, deleted: 5 }, prefix: true

  validates :asaas_payment_id, presence: true, uniqueness: true
  validates :asaas_installment_id, presence: true

  # AsaaS emits both `PAYMENT_RECEIVED` (bank reported the money in) and
  # `PAYMENT_CONFIRMED` (settlement window closed). Either counts as "money
  # in" from the sales flow's point of view.
  def paid?
    status_received? || status_confirmed?
  end
end
