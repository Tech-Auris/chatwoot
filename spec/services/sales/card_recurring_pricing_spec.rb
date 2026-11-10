require 'rails_helper'

RSpec.describe Sales::CardRecurringPricing do
  let(:quote) do
    create(:sales_quote, billing_cycle: :annual, subtotal_amount: 1_395_000, discount_amount: 0, total_amount: 1_395_000)
  end

  before do
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Auris', unit_amount: 1_200_000, recurring_interval: 'year')
    create(:sales_quote_item, sales_quote: quote, name: 'Implantação', unit_amount: 195_000, recurring_interval: nil)
  end

  it 'splits the total, setup fee included, by the months of the plan' do
    expect(described_class.charge_for(quote)).to eq(116_250)
    expect(described_class.residue_for(quote)).to eq(0)
  end

  # After the first cycle the setup fee is gone and the subscription goes back
  # to list price.
  it 'renews without the setup fee' do
    expect(described_class.renewal_charge_for(quote)).to eq(100_000)
  end

  it 'renews at list price, without the proposal discount' do
    quote.update!(discount_amount: 139_500, total_amount: 1_255_500)

    expect(described_class.charge_for(quote)).to eq(104_625)
    expect(described_class.renewal_charge_for(quote)).to eq(100_000)
  end
end
