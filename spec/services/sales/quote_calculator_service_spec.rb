require 'rails_helper'

RSpec.describe Sales::QuoteCalculatorService do
  def calculate(items, **)
    described_class.new(items: items, **).perform
  end

  # `SalesDiscount#snapshot`, the shape the controller hands the calculator.
  def discount(name, percent, products: [], expires: false)
    { discount_id: name.hash, name: name, label: build(:sales_discount, name: name, percent: percent).label, percent: percent,
      stripe_product_ids: products, expires_with_reservation: expires }
  end

  let(:cart) { [{ unit_amount: 89_700, quantity: 1 }, { unit_amount: 9900, quantity: 2 }] }
  let(:meeting) { discount('Reunião', 10, expires: true) }
  let(:referral) { discount('Indicação', 5) }

  it 'adds up the cart' do
    expect(calculate(cart).subtotal).to eq(109_500)
  end

  it 'applies an order-wide discount' do
    result = calculate(cart, discounts: [meeting])

    expect(result.discount).to eq(10_950)
    expect(result.total).to eq(98_550)
  end

  # 10% + 5% is 15% of the same base, not 5% of what the 10% left.
  it 'adds up the order-wide percentages instead of compounding them' do
    result = calculate(cart, discounts: [meeting, referral])

    expect(result.discount).to eq(10_950 + 5475)
    expect(result.summary).to eq('10% reunião + 5% indicação')
  end

  # `meeting_discount_amount` isolates what ends with the reservation so
  # callers can undo it cleanly when it expires without recomputing the
  # whole result.
  it 'exposes the portion that expires with the reservation separately' do
    result = calculate(cart, discounts: [meeting, referral])

    expect(result.meeting_discount_amount).to eq(10_950)
  end

  it 'zeroes meeting_discount_amount when nothing expires with the reservation' do
    expect(calculate(cart, discounts: [referral]).meeting_discount_amount).to eq(0)
  end

  it 'returns each applied discount with its amount' do
    result = calculate(cart, discounts: [meeting, referral])

    expect(result.applied_discounts.map { |applied| [applied[:name], applied[:amount]] })
      .to eq([['Reunião', 10_950], ['Indicação', 5475]])
  end

  # The seller and the customer both read this line; it is also what goes to the
  # Stripe invoice so the charge explains itself there.
  it 'says what each discount was' do
    result = calculate(cart, discounts: [meeting], coupon: { id: 'c1', name: 'Parceiro', percent_off: 15 })

    expect(result.summary).to eq('10% reunião + cupom Parceiro (15%)')
  end

  it 'stacks a discount with a percentage coupon' do
    result = calculate(cart, discounts: [meeting], coupon: { percent_off: 15 })

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
                       discounts: [meeting], coupon: { percent_off: 95 }, pix_discount_percent: 10)

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

  # A discount tied to products (an "isenção") only touches the lines sold
  # from them, and runs before the order-wide ones so those do not chew a
  # line that was already zeroed.
  describe 'discount on specific products' do
    let(:config_api) { discount('Isenção config. integração API', 100, products: ['prod_config_api']) }
    let(:setup) { discount('Isenção implantação', 100, products: ['prod_setup']) }
    let(:full_cart) do
      [{ unit_amount: 479_400, quantity: 1, name: 'Plataforma Auris', stripe_product_id: 'prod_platform' },
       { unit_amount: 150_000, quantity: 1, name: 'Implantação', stripe_product_id: 'prod_setup' },
       { unit_amount: 80_000, quantity: 1, name: 'Config. de Integração API', stripe_product_id: 'prod_config_api' },
       { unit_amount: 60_000, quantity: 1, name: 'Desenv. de Integração API', stripe_product_id: 'prod_dev_api' },
       { unit_amount: 40_000, quantity: 1, name: 'Configuração de API Meta', stripe_product_id: 'prod_meta' }]
    end

    it 'only takes the line of its product' do
      result = calculate(full_cart, discounts: [config_api])

      expect(result.discount).to eq(80_000)
      expect(result.waivers_amount).to eq(80_000)
      expect(result.summary).to eq('isenção config. integração API')
    end

    it 'stacks the four discounts, with the percentages on what the waivers left' do
      result = calculate(full_cart, discounts: [setup, config_api, meeting, referral])

      # subtotal 809_400 → waivers 230_000 → eligible 579_400 → 15% = 86_910.
      expect(result.discount).to eq(230_000 + 57_940 + 28_970)
      expect(result.summary).to eq('isenção implantação + isenção config. integração API + 10% reunião + 5% indicação')
    end

    it 'does not apply when its product is not in the cart' do
      result = calculate(cart, discounts: [setup])

      expect(result.discount).to eq(0)
      expect(result.applied_discounts).to be_empty
    end

    it 'takes a partial percent of the line' do
      result = calculate(full_cart, discounts: [discount('Implantação', 50, products: ['prod_setup'])])

      expect(result.discount).to eq(75_000)
      expect(result.summary).to eq('50% implantação')
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
      result = calculate(cart_with_setup, discounts: [meeting], coupon: scoped_coupon)

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

    context 'when the scoped coupon carries an amount_off instead of a percent' do
      let(:fixed_scoped_coupon) do
        { id: 'setup_r2k', name: 'Desconto Implantação Semestral', amount_off: 200_000, applies_to_products: ['prod_setup'] }
      end

      it 'applies the fixed amount only against the scoped product line' do
        result = calculate(cart_with_setup, coupon: fixed_scoped_coupon)

        # subtotal 119_700 → 200_000 off setup line, capped at line total 30_000.
        expect(result.discount).to eq(30_000)
        expect(result.total).to eq(89_700)
        expect(result.summary).to eq('cupom Desconto Implantação Semestral')
      end

      it 'takes the coupon amount when it fits under the scoped line' do
        cart_with_bigger_setup = [
          { unit_amount: 598_200, quantity: 1, name: 'Plataforma Auris', stripe_product_id: 'prod_platform' },
          { unit_amount: 300_000, quantity: 1, name: 'Implantação', stripe_product_id: 'prod_setup' }
        ]
        result = calculate(cart_with_bigger_setup, coupon: fixed_scoped_coupon)

        # subtotal 898_200 → 200_000 off (fits under the 300_000 setup line).
        expect(result.discount).to eq(200_000)
        expect(result.total).to eq(698_200)
      end
    end
  end
end
