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

  describe '#fields=' do
    it 'drops rows without a key and fills the defaults, from the form rows by index' do
      erp_source = build(:erp_source, fields: {
                           '0' => { 'key' => ' senha ', 'label' => '', 'type' => 'text', 'secret' => '1' },
                           '1' => { 'key' => '', 'label' => 'ignored' }
                         })

      expect(erp_source.fields).to eq([{ 'key' => 'senha', 'label' => 'senha', 'type' => 'text', 'secret' => true }])
      expect(erp_source.secret_keys).to eq(['senha'])
    end

    it 'refuses repeated keys and unknown types' do
      erp_source = build(:erp_source, fields: [{ 'key' => 'a' }, { 'key' => 'a', 'type' => 'date' }])

      expect(erp_source).not_to be_valid
      expect(erp_source.errors[:fields].join).to include('a').and include('date')
    end
  end
end
