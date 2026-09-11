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

  # The seller can waive the "Integração via API" line during the meeting;
  # the whole line comes off the total and the summary names the reason.
  # Matched by exact product name — that's the fragility the operator opts
  # into.
  describe 'api_integration waiver' do
    let(:cart_with_api) do
      [{ unit_amount: 89_700, quantity: 1, name: 'Plataforma Auris' },
       { unit_amount: 50_000, quantity: 1, name: 'Integração via API' }]
    end

    it 'subtracts the whole line for the waived item' do
      result = calculate(cart_with_api, api_integration_waived: true)

      expect(result.subtotal).to eq(139_700)
      expect(result.discount).to eq(50_000)
      expect(result.total).to eq(89_700)
      expect(result.summary).to include('isenção integração via API')
    end

    # The waiver runs before the meeting %, so the 10% only chews the line
    # that survived it. Otherwise the seller would double-discount the
    # zeroed-out item.
    it 'stacks with the meeting discount, calculating the % after the waiver' do
      result = calculate(cart_with_api, meeting_discount: true, api_integration_waived: true)

      # subtotal 139_700 → waiver 50_000 → eligible 89_700 → meeting 8_970.
      expect(result.discount).to eq(8_970 + 50_000)
      expect(result.summary).to eq('isenção integração via API + 10% reunião')
    end

    it 'is a no-op when the cart has no API integration item' do
      result = calculate(cart, api_integration_waived: true)

      expect(result.discount).to eq(0)
      expect(result.summary).to be_nil
    end

    # The same product ships under a second name in Stripe production
    # ("Desenvolvimento de Integração API"). The waiver has to catch both,
    # otherwise the checkbox appears but does nothing on the newer name.
    it 'also waives the line named "Desenvolvimento de Integração API"' do
      cart_with_alt_name = [
        { unit_amount: 89_700, quantity: 1, name: 'Plataforma Auris' },
        { unit_amount: 50_000, quantity: 1, name: 'Desenvolvimento de Integração API' }
      ]
      result = calculate(cart_with_alt_name, api_integration_waived: true)

      expect(result.discount).to eq(50_000)
      expect(result.total).to eq(89_700)
      expect(result.summary).to include('isenção integração via API')
    end
  end

  # Stripe coupons scoped to specific products (`applies_to.products`) are
  # the way the operator sets up product-level waivers ("Isenção da
  # Implantação — 100%"). The percentage only touches the lines whose
  # `stripe_product_id` matches — applying it over the whole cart was
  # zeroing out unrelated items.
  describe 'coupon scoped to specific products' do
    let(:cart_with_setup) do
      [{ unit_amount: 89_700, quantity: 1, name: 'Plataforma Auris', stripe_product_id: 'prod_platform' },
       { unit_amount: 30_000, quantity: 1, name: 'Implantação', stripe_product_id: 'prod_setup' }]
    end
    let(:scoped_coupon) do
      { id: 'setup_waiver', name: 'Isenção da Implantação', percent_off: 100, applies_to_products: ['prod_setup'] }
    end

    it 'only discounts the matching line, not the whole cart' do
      result = calculate(cart_with_setup, coupon: scoped_coupon)

      # subtotal 119_700; the scoped waiver only takes off the 30_000 setup line.
      expect(result.discount).to eq(30_000)
      expect(result.total).to eq(89_700)
      expect(result.summary).to eq('cupom Isenção da Implantação (100%)')
    end

    it 'runs the meeting discount on what is left after the scoped waiver' do
      result = calculate(cart_with_setup, meeting_discount: true, coupon: scoped_coupon)

      # subtotal 119_700 → waiver 30_000 → eligible 89_700 → meeting 8_970.
      expect(result.discount).to eq(30_000 + 8_970)
      expect(result.total).to eq(80_730)
      expect(result.summary).to eq('cupom Isenção da Implantação (100%) + 10% reunião')
    end

    it 'is a no-op when the cart has none of the coupon products' do
      result = calculate(cart, coupon: scoped_coupon)

      expect(result.discount).to eq(0)
      expect(result.summary).to be_nil
    end
  end
end
