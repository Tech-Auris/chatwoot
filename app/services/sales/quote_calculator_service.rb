# Prices a proposal: what the items add up to, what comes off, and a sentence
# saying why.
#
# The arithmetic lives here rather than in Stripe because the discounts stack in
# ways Stripe does not model — a coupon plus the meeting discount plus, later,
# the PIX discount. The breakdown travels to the Stripe invoice as a description
# so the charge explains itself there too.
#
# Order matters:
#   1. Waivers (isenções) run first — full-price cuts on a specific item
#      (API integration checkbox, a coupon scoped to a Stripe product like
#      "Isenção da Implantação — 100%").
#   2. Meeting discount runs on what is left, so the seller does not double-
#      discount the line that was already zeroed by a waiver.
#   3. Untargeted percentage coupons run alongside the meeting discount on
#      the same "eligible" base.
#   4. PIX runs at the payment step on the sum still on the table.
class Sales::QuoteCalculatorService
  MEETING_DISCOUNT_PERCENT = 10
  # Matched by exact product name — the seller opts in through a checkbox
  # in the plan builder and the whole line comes off the total. A rename
  # on the Stripe side needs a matching bump here; kept as a constant so
  # a rename is a one-line change.
  API_INTEGRATION_ITEM_NAME = 'Integração via API'.freeze

  Result = Struct.new(:subtotal, :discount, :total, :summary, keyword_init: true)

  attr_reader :items, :meeting_discount, :coupon, :pix_discount_percent, :api_integration_waived

  def initialize(items:, meeting_discount: false, coupon: nil, pix_discount_percent: 0, api_integration_waived: false)
    @items = items
    @meeting_discount = meeting_discount
    @coupon = coupon&.symbolize_keys
    @pix_discount_percent = pix_discount_percent
    @api_integration_waived = api_integration_waived
  end

  def perform
    subtotal = items.sum { |item| line_total(item) }
    parts = discount_parts(subtotal)
    discount = [parts.sum { |part| part[:amount] }, subtotal].min

    Result.new(
      subtotal: subtotal,
      discount: discount,
      total: subtotal - discount,
      summary: parts.pluck(:label).join(' + ').presence
    )
  end

  private

  def line_total(item)
    item[:unit_amount].to_i * (item[:quantity].presence || 1).to_i
  end

  def discount_parts(subtotal)
    waivers = [api_integration_part, scoped_coupon_waiver_part].compact
    waived_amount = waivers.sum { |part| part[:amount] }
    eligible = [subtotal - waived_amount, 0].max

    # A scoped coupon never falls back to the un-scoped branch — if none
    # of its products are in the cart, the discount is simply zero, not
    # a 100%-off over unrelated lines.
    unscoped_coupon = coupon_scoped_to_products? ? nil : coupon_part(eligible)

    [
      *waivers,
      meeting_part(eligible),
      unscoped_coupon,
      pix_part(eligible)
    ].compact
  end

  # A full-price waiver on the API integration item: the entire line
  # (unit × quantity) is subtracted, matched by the product name so the
  # cart can still display the item as usual and the audit trail keeps
  # the reason ("isenção integração via API") next to the other parts.
  def api_integration_part
    return nil unless api_integration_waived

    amount = items.select { |item| item[:name].to_s == API_INTEGRATION_ITEM_NAME }
                  .sum { |item| line_total(item) }
    return nil if amount.zero?

    { amount: amount, label: 'isenção integração via API' }
  end

  # Stripe coupons scoped to a specific product with 100% off are the way
  # the operator sets up product-level waivers (e.g. "Isenção da
  # Implantação — 100%"). Treat them as waivers, not as an untargeted
  # percentage over the whole cart — the coupon percentage only touches
  # the lines whose `stripe_product_id` matches the coupon's
  # `applies_to.products`.
  def scoped_coupon_waiver_part
    return nil if coupon.blank?
    return nil unless coupon_scoped_to_products?
    return nil if coupon[:percent_off].to_f.zero?

    scoped_subtotal = items.select { |item| coupon_products.include?(item[:stripe_product_id].to_s) }
                           .sum { |item| line_total(item) }
    return nil if scoped_subtotal.zero?

    amount = percent_of(scoped_subtotal, coupon[:percent_off])
    { amount: [amount, scoped_subtotal].min, label: "cupom #{coupon_name} (#{format_percent(coupon[:percent_off])}%)" }
  end

  def meeting_part(base)
    return nil unless meeting_discount
    return nil if base.zero?

    { amount: percent_of(base, MEETING_DISCOUNT_PERCENT), label: "#{MEETING_DISCOUNT_PERCENT}% reunião" }
  end

  # Untargeted coupon: applies to whatever is still on the table after
  # waivers. A Stripe coupon is either a percentage or a fixed amount,
  # never both — the scoped-percentage branch is handled by
  # `scoped_coupon_waiver_part`.
  def coupon_part(base)
    return nil if coupon.blank?

    if coupon[:percent_off].present?
      { amount: percent_of(base, coupon[:percent_off]), label: "cupom #{coupon_name} (#{format_percent(coupon[:percent_off])}%)" }
    else
      { amount: coupon[:amount_off].to_i, label: "cupom #{coupon_name}" }
    end
  end

  def coupon_scoped_to_products?
    coupon_products.any?
  end

  def coupon_products
    @coupon_products ||= Array(coupon&.dig(:applies_to_products)).map(&:to_s)
  end

  def coupon_name
    coupon[:name].presence || coupon[:id]
  end

  # Only applies once the customer picks PIX, at the payment step.
  def pix_part(base)
    return nil if pix_discount_percent.to_i.zero?

    { amount: percent_of(base, pix_discount_percent), label: "#{format_percent(pix_discount_percent)}% pix" }
  end

  def percent_of(amount, percent)
    (amount * percent.to_f / 100).round
  end

  # "10% reunião" reads better than "10.0% reunião"; a broken percentage keeps
  # its decimals.
  def format_percent(percent)
    value = percent.to_f
    (value % 1).zero? ? value.to_i : value
  end
end
