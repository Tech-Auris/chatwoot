# Trail of what happened to a proposal — created, reserved, opened by the
# prospect, signed, paid. It answers "did the prospect ever open the link?",
# which neither ClickUp nor Stripe can tell us.
class SalesQuoteEvent < ApplicationRecord
  belongs_to :sales_quote
  belongs_to :user, optional: true

  validates :event, presence: true
end
