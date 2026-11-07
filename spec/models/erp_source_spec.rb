require 'rails_helper'

RSpec.describe ErpSource do
  it 'is created with the id it has in the Supabase integration_type table' do
    erp_source = described_class.create!(id: 17, name: 'Novo ERP')

    expect(erp_source.reload.id).to eq(17)
  end

  it 'needs that id and a unique name' do
    create(:erp_source, name: 'Feegow')

    expect(described_class.new(name: 'Sem id')).not_to be_valid
    expect(described_class.new(id: 99, name: 'Feegow')).not_to be_valid
  end

  it 'cannot be deleted while an account uses it, only deactivated' do
    erp_source = create(:erp_source)
    create(:account, erp_source: erp_source)

    expect(erp_source.destroy).to be(false)
    expect(erp_source.update(active: false)).to be(true)
  end
end
