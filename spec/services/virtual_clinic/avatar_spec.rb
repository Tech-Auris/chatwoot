require 'rails_helper'

RSpec.describe VirtualClinic::Avatar do
  let(:look) do
    { 'body' => 'Body_32x32_07', 'eyes' => 'Eyes_32x32_02', 'outfit' => 'Outfit_05_32x32_02', 'accessory' => 'Accessory_15_Glasses_32x32_01' }
  end

  it 'keeps a look made of layers of the right parts' do
    expect(described_class.sanitize(look)).to eq(look)
    expect(described_class.paths(look)).to include('9_avatar/Accessory_15_Glasses_32x32_01.png')
  end

  it 'drops anything that is not a look' do
    expect(described_class.sanitize(nil)).to be_nil
    expect(described_class.sanitize(look.except('eyes'))).to be_nil
    expect(described_class.sanitize(look.merge('hat' => 'Hat_01'))).to be_nil
    expect(described_class.sanitize(look.merge('hair' => 'Body_32x32_01'))).to be_nil
    expect(described_class.sanitize(look.merge('hair' => 'Hairstyle_01/../x'))).to be_nil
  end
end
