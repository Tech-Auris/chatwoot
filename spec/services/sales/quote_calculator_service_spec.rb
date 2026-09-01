require 'rails_helper'

RSpec.describe Sales::QuoteCalculatorService do
  def calculate(items, **)
    described_class.new(items: items, **).perform
  end

  let(:cart) { [{ unit_amount: 89_700, quantity: 1 }, { unit_amount: 9900, quantity: 2 }] }

  it 'adds up the cart' do
    expect(calculate(cart).subtotal).to eq(109_500)
  end

  it 'applies the meeting discount' do
    result = calculate(cart, meeting_discount: true)

    expect(result.discount).to eq(10_950)
    expect(result.total).to eq(98_550)
  end

  # The seller and the customer both read this line; it is also what goes to the
  # Stripe invoice so the charge explains itself there.
  it 'says what each discount was' do
    result = calculate(cart, meeting_discount: true, coupon: { id: 'c1', name: 'Parceiro', percent_off: 15 })

    expect(result.summary).to eq('10% reunião + cupom Parceiro (15%)')
  end

  it 'stacks the meeting discount with a percentage coupon' do
    result = calculate(cart, meeting_discount: true, coupon: { percent_off: 15 })

    expect(result.discount).to eq(10_950 + 16_425)
  end

  it 'applies a fixed-amount coupon in cents' do
    result = calculate(cart, coupon: { id: 'c2', name: 'Cortesia', amount_off: 5000 })

    expect(result.discount).to eq(5000)
    expect(result.summary).to eq('cupom Cortesia')
  end

  # Only at the payment step, and only for PIX — but the arithmetic lives in one
  # place so the screen and the checkout can never disagree.
  it 'applies the pix discount when the customer picks it' do
    result = calculate(cart, pix_discount_percent: 5)

    expect(result.discount).to eq(5475)
    expect(result.summary).to eq('5% pix')
  end

  it 'combines the three without ever giving money away' do
    result = calculate([{ unit_amount: 10_000, quantity: 1 }],
                       meeting_discount: true, coupon: { percent_off: 95 }, pix_discount_percent: 10)

    expect(result.discount).to eq(10_000)
    expect(result.total).to eq(0)
  end

  it 'reads a whole percentage without a decimal' do
    expect(calculate(cart, coupon: { id: 'c1', percent_off: 15.0 }).summary).to eq('cupom c1 (15%)')
  end

  it 'keeps the decimals of a broken percentage' do
    expect(calculate(cart, coupon: { id: 'c1', percent_off: 12.5 }).summary).to eq('cupom c1 (12.5%)')
  end

  it 'has no summary when nothing was discounted' do
    expect(calculate(cart).summary).to be_nil
  end
end
