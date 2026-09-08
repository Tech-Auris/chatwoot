# Prices a proposal: what the items add up to, what comes off, and a sentence
# saying why.
#
# The arithmetic lives here rather than in Stripe because the discounts stack in
# ways Stripe does not model — a coupon plus the meeting discount plus, later,
# the PIX discount. The breakdown travels to the Stripe invoice as a description
# so the charge explains itself there too.
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
    subtotal = items.sum { |item| item[:unit_amount].to_i * (item[:quantity].presence || 1).to_i }
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

  def discount_parts(subtotal)
    [meeting_part(subtotal), coupon_part(subtotal), pix_part(subtotal), api_integration_part].compact
  end

  # A full-price waiver on the API integration item: the entire line
  # (unit × quantity) is subtracted, matched by the product name so the
  # cart can still display the item as usual and the audit trail keeps
  # the reason ("isenção integração via API") next to the other parts.
  def api_integration_part
    return nil unless api_integration_waived

    amount = items.select { |item| item[:name].to_s == API_INTEGRATION_ITEM_NAME }
                  .sum { |item| item[:unit_amount].to_i * (item[:quantity].presence || 1).to_i }
    return nil if amount.zero?

    { amount: amount, label: 'isenção integração via API' }
  end

  def meeting_part(subtotal)
    return nil unless meeting_discount

    { amount: percent_of(subtotal, MEETING_DISCOUNT_PERCENT), label: "#{MEETING_DISCOUNT_PERCENT}% reunião" }
  end

  # A Stripe coupon is either a percentage or a fixed amount, never both.
  def coupon_part(subtotal)
    return nil if coupon.blank?

    if coupon[:percent_off].present?
      { amount: percent_of(subtotal, coupon[:percent_off]), label: "cupom #{coupon_name} (#{format_percent(coupon[:percent_off])}%)" }
    else
      { amount: coupon[:amount_off].to_i, label: "cupom #{coupon_name}" }
    end
  end

  def coupon_name
    coupon[:name].presence || coupon[:id]
  end

  # Only applies once the customer picks PIX, at the payment step.
  def pix_part(subtotal)
    return nil if pix_discount_percent.to_i.zero?

    { amount: percent_of(subtotal, pix_discount_percent), label: "#{format_percent(pix_discount_percent)}% pix" }
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
