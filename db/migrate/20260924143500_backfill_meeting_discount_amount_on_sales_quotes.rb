# Re-runs `Sales::QuoteCalculatorService` against every existing quote whose
# seller applied the meeting discount, so `meeting_discount_amount` matches
# the portion of `discount_amount` that came from the 10% courtesy. New rows
# already save this via `apply_totals`; this pass covers the historical ones
# so `effective_total_amount` on the model can subtract the right amount when
# a reservation has expired.
#
# Ignores the coupon during the recompute — a scoped Stripe coupon is fetched
# live from Stripe on the create path, and we do not want the migration to
# depend on Stripe being reachable. The eligible base for the meeting portion
# is `subtotal - api_integration_waiver`, which does not depend on the coupon
# for the vast majority of accounts. Quotes with a scoped coupon in the cart
# will be slightly overestimated (by 10% of the scoped-coupon amount); the
# next time the seller edits or renews the proposal, `apply_totals` writes
# the exact number back.
class BackfillMeetingDiscountAmountOnSalesQuotes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    SalesQuote.where(meeting_discount: true, meeting_discount_amount: 0).find_each(batch_size: 200) do |quote|
      calculator_input = quote.items.map do |item|
        {
          unit_amount: item.unit_amount,
          quantity: item.quantity,
          name: item.name,
          stripe_product_id: item.stripe_product_id
        }
      end

      result = Sales::QuoteCalculatorService.new(
        items: calculator_input,
        meeting_discount: true,
        coupon: nil,
        api_integration_waived: quote.api_integration_waived
      ).perform

      next if result.meeting_discount_amount.to_i.zero?

      # `update_column` — bypasses validations and callbacks: the intent
      # is a one-shot fill in place, not a state change.
      quote.update_column(:meeting_discount_amount, result.meeting_discount_amount) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    # No-op: the column stays; a reversal would just erase computed values.
  end
end
