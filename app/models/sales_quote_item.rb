# One line of a proposal. Everything but the price id is a snapshot taken when
# the line was added, so the proposal keeps reading the same after the Stripe
# catalogue changes.
# == Schema Information
#
# Table name: sales_quote_items
#
#  id                 :bigint           not null, primary key
#  kind               :integer          default("plan"), not null
#  name               :string           not null
#  quantity           :integer          default(1), not null
#  recurring_interval :string
#  unit_amount        :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  sales_quote_id     :bigint           not null
#  stripe_price_id    :string           not null
#  stripe_product_id  :string
#
# Indexes
#
#  index_sales_quote_items_on_sales_quote_id  (sales_quote_id)
#
# Foreign Keys
#
#  fk_rails_...  (sales_quote_id => sales_quotes.id)
#
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
