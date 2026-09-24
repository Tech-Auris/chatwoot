# Reruns `Sales::QuoteCalculatorService` against existing quotes so
# `waivers_amount` matches the item-targeted portion of `discount_amount`
# (api_integration waiver + scoped coupon). New rows already save this
# via `apply_totals`; this pass covers the historical ones so the
# ClickUp CRM sync can compute the implementation value correctly on any
# resync of an old proposal.
#
# Ignores the coupon during the recompute — a scoped Stripe coupon is
# fetched live from Stripe on the create path, and we do not want the
# migration to depend on Stripe being reachable. A row whose api
# integration was NOT waived and whose coupon was scoped will stay with
# `waivers_amount = 0` until the next `apply_totals` writes the exact
# number; the CRM sync then defaults to the raw implementation subtotal,
# which is the same value the pipeline had before this migration ran, so
# nothing regresses for historical rows we cannot recompute.
class BackfillWaiversAmountOnSalesQuotes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    SalesQuote.where(waivers_amount: 0).find_each(batch_size: 200) do |quote|
      next unless quote.api_integration_waived || quote.coupon_id.present?

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
        meeting_discount: quote.meeting_discount,
        coupon: nil,
        api_integration_waived: quote.api_integration_waived
      ).perform

      next if result.waivers_amount.to_i.zero?

      quote.update_column(:waivers_amount, result.waivers_amount) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    # No-op — reversal would just erase computed values.
  end
end
