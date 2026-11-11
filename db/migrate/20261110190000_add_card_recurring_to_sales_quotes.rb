# The recurring card is off by default and only reaches the public page after
# the seller enables it from the Reservations grid — same shape as
# `boleto_enabled_at`.
#
# `payment_overdue_since` is when the oldest unpaid Stripe invoice of the
# recurring card fell due. Empty while the customer is up to date; the daily
# suspension job reads it.
class AddCardRecurringToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_quotes, :card_recurring_enabled_at, :datetime
    add_column :sales_quotes, :payment_overdue_since, :datetime
  end
end
