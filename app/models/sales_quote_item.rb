# One line of a proposal. Everything but the price id is a snapshot taken when
# the line was added, so the proposal keeps reading the same after the Stripe
# catalogue changes.
class SalesQuoteItem < ApplicationRecord
  belongs_to :sales_quote

  enum :kind, { plan: 0, addon: 1 }, prefix: true

  validates :stripe_price_id, :name, presence: true
  validates :unit_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  def total_amount
    unit_amount * quantity
  end
end
