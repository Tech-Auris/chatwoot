# Trail of what happened to a proposal — created, reserved, opened by the
# prospect, signed, paid. It answers "did the prospect ever open the link?",
# which neither ClickUp nor Stripe can tell us.
# == Schema Information
#
# Table name: sales_quote_events
#
#  id             :bigint           not null, primary key
#  event          :string           not null
#  metadata       :jsonb            not null
#  created_at     :datetime         not null
#  sales_quote_id :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_sales_quote_events_on_sales_quote_id                 (sales_quote_id)
#  index_sales_quote_events_on_sales_quote_id_and_created_at  (sales_quote_id,created_at)
#  index_sales_quote_events_on_user_id                        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (sales_quote_id => sales_quotes.id)
#  fk_rails_...  (user_id => users.id)
#
class SalesQuoteEvent < ApplicationRecord
  belongs_to :sales_quote
  belongs_to :user, optional: true

  validates :event, presence: true
end
