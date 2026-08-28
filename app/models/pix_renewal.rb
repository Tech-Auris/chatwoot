# One billing period of a customer who pays by PIX.
#
# A card subscription renews itself in Stripe; PIX cannot back a recurring
# subscription, so each cycle is charged again by hand. This record is what
# remembers that a cycle is ending, so nobody has to.
#
# Periods form a chain: settling one opens the next, a cancelled one ends it.
# == Schema Information
#
# Table name: pix_renewals
#
#  id                 :bigint           not null, primary key
#  amount             :integer          not null
#  due_on             :date             not null
#  hosted_invoice_url :string
#  paid_at            :datetime
#  paid_via           :string
#  status             :integer          default("pending"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  sales_quote_id     :bigint           not null
#  stripe_invoice_id  :string
#
# Indexes
#
#  index_pix_renewals_on_account_id         (account_id)
#  index_pix_renewals_on_sales_quote_id     (sales_quote_id)
#  index_pix_renewals_on_status_and_due_on  (status,due_on)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (sales_quote_id => sales_quotes.id)
#
class PixRenewal < ApplicationRecord
  # How far ahead a period starts being flagged on the screen.
  ALERT_WINDOW_DAYS = 7

  # How long each cycle covers.
  CYCLE_MONTHS = { 'monthly' => 1, 'semiannual' => 6, 'annual' => 12 }.freeze

  belongs_to :account
  belongs_to :sales_quote

  enum :status, { pending: 0, invoiced: 1, paid: 2, cancelled: 3 }, prefix: true

  validates :due_on, :amount, presence: true

  scope :open_periods, -> { where(status: [:pending, :invoiced]) }
  scope :alerting, -> { open_periods.where(due_on: ..Date.current + ALERT_WINDOW_DAYS) }
  scope :overdue, -> { open_periods.where(due_on: ...Date.current) }

  def self.months_for(billing_cycle)
    CYCLE_MONTHS.fetch(billing_cycle.to_s, 1)
  end

  def overdue?
    !status_paid? && !status_cancelled? && due_on < Date.current
  end
end
