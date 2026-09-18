# One row per AsaaS payment inside an instalment book: for a semiannual
# boleto sale that is six rows, twelve for annual. The webhook writes here
# every time AsaaS reports a status change on a payment, so the audit trail
# holds the full history of every parcel (paid, overdue, refunded) without
# the finance team having to poll AsaaS by hand.
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
