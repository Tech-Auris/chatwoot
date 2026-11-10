require 'rails_helper'

RSpec.describe SalesDiscount do
  it 'requires a name and a percent between 0 and 100' do
    expect(build(:sales_discount, name: '')).not_to be_valid
    expect(build(:sales_discount, percent: 0)).not_to be_valid
    expect(build(:sales_discount, percent: 101)).not_to be_valid
    expect(build(:sales_discount, percent: 100)).to be_valid
  end

  it 'drops blank and repeated product ids' do
    discount = create(:sales_discount, stripe_product_ids: ['prod_a', ' ', 'prod_a'])

    expect(discount.stripe_product_ids).to eq(['prod_a'])
  end

  describe '#label' do
    it 'leads with the percent on a partial discount' do
      expect(build(:sales_discount, name: 'Reunião', percent: 10).label).to eq('10% reunião')
    end

    it 'names a full waiver on its own' do
      expect(build(:sales_discount, name: 'Isenção config. integração API', percent: 100).label)
        .to eq('isenção config. integração API')
    end

    it 'keeps the decimals of a broken percentage' do
      expect(build(:sales_discount, name: 'Parceiro', percent: 7.5).label).to eq('7.5% parceiro')
    end
  end
end
