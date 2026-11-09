# A discount the sales team can stack on a proposal, kept in Super Admin →
# Commercial → Descontos so a new one (or a different product) needs no deploy.
#
# With no products it takes its percent off the whole order; with products it
# only touches the lines sold from those Stripe products (an "isenção" is just
# 100% on a product). Proposals keep their own copy of what was applied
# (`SalesQuote#applied_discounts`), so editing one here never moves a proposal
# that already exists.
class SalesDiscount < ApplicationRecord
  validates :name, presence: true
  validates :percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  before_validation :clean_product_ids

  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(active: true) }

  def product_scoped?
    stripe_product_ids.any?
  end

  # How the discount reads in the proposal's summary: "10% reunião",
  # "isenção implantação". A full waiver is named on its own; a partial one
  # leads with the percent.
  def label
    name_part = name.sub(/\A./, &:downcase)
    percent.to_d == 100 ? name_part : "#{format_percent}% #{name_part}"
  end

  def snapshot
    { discount_id: id, name: name, label: label, percent: percent.to_f, stripe_product_ids: stripe_product_ids,
      expires_with_reservation: expires_with_reservation }
  end

  private

  def format_percent
    (percent % 1).zero? ? percent.to_i : percent.to_f
  end

  def clean_product_ids
    self.stripe_product_ids = Array(stripe_product_ids).map { |id| id.to_s.strip }.compact_blank.uniq
  end
end
