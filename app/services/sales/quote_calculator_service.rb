# Prices a proposal: what the items add up to, what comes off, and a sentence
# saying why.
#
# The arithmetic lives here rather than in Stripe because the discounts stack in
# ways Stripe does not model — a coupon plus the meeting discount plus, later,
# the PIX discount. The breakdown travels to the Stripe invoice as a description
# so the charge explains itself there too.
#
# Order matters:
#   1. Waivers (isenções) run first — cuts on specific items: the product-scoped
#      discounts from Commercial → Descontos, and a coupon scoped to a Stripe
#      product like "Isenção da Implantação — 100%".
#   2. Order-wide discounts (reunião, indicação…) run on what is left and add
#      up — 10% + 5% is 15% of the same base, not one on top of the other — so
#      the seller does not double-discount a line a waiver already zeroed.
#   3. Untargeted percentage coupons run alongside them on the same base.
#   4. PIX runs at the payment step on the sum still on the table.
class Sales::QuoteCalculatorService
  Result = Struct.new(:subtotal, :discount, :total, :summary, :meeting_discount_amount, :waivers_amount, :applied_discounts,
                      keyword_init: true)

  attr_reader :items, :discounts, :coupon, :pix_discount_percent

  # `discounts` are `SalesDiscount#snapshot` hashes — the copy the proposal
  # keeps, so pricing a saved proposal never depends on the current catalogue.
  def initialize(items:, discounts: [], coupon: nil, pix_discount_percent: 0)
    @items = items
    @discounts = discounts.map(&:symbolize_keys)
    @coupon = coupon&.symbolize_keys
    @pix_discount_percent = pix_discount_percent
  end

  def perform
    subtotal = items.sum { |item| line_total(item) }
    parts = discount_parts(subtotal)
    discount = [parts.sum { |part| part[:amount] }, subtotal].min
    applied = parts.filter_map { |part| part[:discount]&.merge(amount: part[:amount]) }

    Result.new(
      subtotal: subtotal,
      discount: discount,
      total: subtotal - discount,
      summary: parts.pluck(:label).join(' + ').presence,
      meeting_discount_amount: expiring_amount(applied),
      waivers_amount: parts.select { |part| part[:key] == :waiver }.sum { |part| part[:amount] },
      applied_discounts: applied
    )
  end

  private

  # Whatever only holds while the reservation does (the meeting discount) is
  # peeled back off by `SalesQuote#effective_*` once it expires.
  def expiring_amount(applied)
    applied.select { |part| part[:expires_with_reservation] }.sum { |part| part[:amount] }
  end

  def line_total(item)
    item[:unit_amount].to_i * (item[:quantity].presence || 1).to_i
  end

  def discount_parts(subtotal)
    waivers = [*product_discount_parts, scoped_coupon_waiver_part].compact
    waived_amount = waivers.sum { |part| part[:amount] }
    eligible = [subtotal - waived_amount, 0].max

    # A scoped coupon never falls back to the un-scoped branch — if none
    # of its products are in the cart, the discount is simply zero, not
    # a 100%-off over unrelated lines.
    unscoped_coupon = coupon_scoped_to_products? ? nil : coupon_part(eligible)

    [
      *waivers,
      *order_discount_parts(eligible),
      unscoped_coupon,
      pix_part(eligible)
    ].compact
  end

  # A discount tied to products only touches the lines sold from them; one
  # whose products are not in the cart does not apply at all.
  def product_discount_parts
    discounts.select { |discount| discount[:stripe_product_ids].present? }.filter_map do |discount|
      scoped = items.select { |item| discount[:stripe_product_ids].include?(item[:stripe_product_id].to_s) }
                    .sum { |item| line_total(item) }
      next if scoped.zero?

      { key: :waiver, amount: percent_of(scoped, discount[:percent]), label: discount[:label], discount: discount }
    end
  end

  def order_discount_parts(base)
    return [] if base.zero?

    discounts.select { |discount| discount[:stripe_product_ids].blank? }.map do |discount|
      { amount: percent_of(base, discount[:percent]), label: discount[:label], discount: discount }
    end
  end

  # Stripe coupons scoped to a specific product are the way the operator
  # sets up product-level waivers (e.g. "Isenção da Implantação — 100%"
  # or "Desconto Implantação Semestral — R$ 2.000,00"). Treat them as
  # waivers, not as an untargeted discount over the whole cart — the
  # coupon only touches the lines whose `stripe_product_id` matches the
  # coupon's `applies_to.products`. Handles both flavors:
  #   • percent_off → percentage of the scoped subtotal;
  #   • amount_off  → fixed cut capped at the scoped subtotal so the
  #     line never goes negative.
  def scoped_coupon_waiver_part
    return nil if coupon.blank?
    return nil unless coupon_scoped_to_products?

    scoped_subtotal = scoped_line_subtotal
    return nil if scoped_subtotal.zero?

    scoped_coupon_part(scoped_subtotal)
  end

  def scoped_line_subtotal
    items.select { |item| coupon_products.include?(item[:stripe_product_id].to_s) }
         .sum { |item| line_total(item) }
  end

  def scoped_coupon_part(scoped_subtotal)
    if coupon[:percent_off].to_f.positive?
      amount = percent_of(scoped_subtotal, coupon[:percent_off])
      { key: :waiver, amount: [amount, scoped_subtotal].min,
        label: "cupom #{coupon_name} (#{format_percent(coupon[:percent_off])}%)" }
    elsif coupon[:amount_off].to_i.positive?
      { key: :waiver, amount: [coupon[:amount_off].to_i, scoped_subtotal].min,
        label: "cupom #{coupon_name}" }
    end
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
