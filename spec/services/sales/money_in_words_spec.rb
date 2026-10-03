require 'rails_helper'

RSpec.describe Sales::MoneyInWords do
  {
    184_920 => 'mil oitocentos e quarenta e nove reais e vinte centavos',
    2_219_040 => 'vinte e dois mil cento e noventa reais e quarenta centavos',
    100 => 'um real',
    101 => 'um real e um centavo',
    120_000 => 'mil e duzentos reais',
    10_000_000 => 'cem mil reais',
    100_000_000 => 'um milhão de reais',
    150_000_000 => 'um milhão e quinhentos mil reais'
  }.each do |cents, words|
    it "writes #{cents} cents as \"#{words}\"" do
      expect(described_class.call(cents)).to eq(words)
    end
  end

  it 'writes a plain number for installment counts' do
    expect(described_class.number(12)).to eq('doze')
  end
end
