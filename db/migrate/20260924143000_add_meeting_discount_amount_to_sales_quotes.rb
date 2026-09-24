# Stores the meeting-discount portion of `discount_amount` so the public
# proposal can show the right total when the reservation deadline passes:
# the courtesy 10% only holds while the reservation does, and past that
# point the price has to fall back to what it would be without the meeting
# gesture — but without the courtesy the coupon and the API waiver still
# stand, so we cannot just recompute the whole thing from scratch.
class AddMeetingDiscountAmountToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_quotes, :meeting_discount_amount, :integer, default: 0, null: false
  end
end
