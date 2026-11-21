require 'rails_helper'

RSpec.describe VirtualClinic::Season do
  it 'has Halloween from 16/10 to 31/10 and Christmas from 15/11 to 31/12, every year, and the party always' do
    expect(described_class.active(Date.new(2026, 10, 15)).pluck(:key)).to eq(['party'])
    expect(described_class.active(Date.new(2026, 10, 16)).pluck(:key)).to eq(%w[halloween party])
    expect(described_class.active(Date.new(2026, 11, 14)).pluck(:key)).to eq(['party'])
    expect(described_class.active(Date.new(2026, 11, 15)).pluck(:key)).to eq(%w[christmas party])
    expect(described_class.active(Date.new(2027, 12, 31)).pluck(:key)).to eq(%w[christmas party])
    expect(described_class.active(Date.new(2027, 1, 1)).pluck(:key)).to eq(['party'])
  end
end
