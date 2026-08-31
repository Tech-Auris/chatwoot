require 'rails_helper'

RSpec.describe Sales::PixCodeService do
  # The company's own static code: key, name and city, with no amount.
  let(:static_code) do
    '00020101021126360014br.gov.bcb.pix0114618188670001435204000053039865802BR5905AURIS6009SAO PAULO62070503***6304BF67'
  end

  # Independent of the service, so a wrong checksum cannot pass by agreeing with
  # itself. This is the calculation every bank app runs before accepting a code.
  def crc16(body)
    crc = body.each_byte.reduce(0xFFFF) do |acc, byte|
      8.times.reduce(acc ^ (byte << 8)) do |value, _|
        value.anybits?(0x8000) ? ((value << 1) ^ 0x1021) & 0xFFFF : (value << 1) & 0xFFFF
      end
    end

    format('%04X', crc)
  end

  def fields_of(code)
    result = {}
    cursor = 0
    while cursor < code.length
      id = code[cursor, 2]
      length = code[cursor + 2, 2].to_i
      result[id] = code[cursor + 4, length]
      cursor += 4 + length
    end
    result
  end

  it 'writes the total into the code' do
    result = described_class.new(payload: static_code, amount_cents: 1_286_760).perform

    expect(fields_of(result)['54']).to eq('12867.60')
  end

  it 'closes the code with a checksum a bank app will accept' do
    result = described_class.new(payload: static_code, amount_cents: 1_286_760).perform

    expect(result[-4..]).to eq(crc16(result[0...-4]))
  end

  it 'keeps the account it is paying' do
    result = described_class.new(payload: static_code, amount_cents: 50_000).perform

    expect(fields_of(result)['26']).to eq('0014br.gov.bcb.pix011461818867000143')
    expect(fields_of(result).values_at('53', '58', '59')).to eq(%w[986 BR AURIS])
  end

  # Readers walk the fields in order; an amount written after the country code
  # is a code some apps refuse.
  it 'writes the fields in ascending order' do
    result = described_class.new(payload: static_code, amount_cents: 50_000).perform

    expect(fields_of(result).keys).to eq(fields_of(result).keys.sort)
  end

  it 'replaces an amount the code already carried' do
    with_amount = described_class.new(payload: static_code, amount_cents: 50_000).perform

    result = described_class.new(payload: with_amount, amount_cents: 120_000).perform

    expect(fields_of(result)['54']).to eq('1200.00')
    expect(result[-4..]).to eq(crc16(result[0...-4]))
  end

  it 'hands back the static code when there is nothing to charge' do
    expect(described_class.new(payload: static_code, amount_cents: 0).perform).to eq(static_code)
  end

  # A code we cannot take apart is still one the customer can pay by typing the
  # amount, which is better than a code nobody can pay at all.
  it 'hands back a code it cannot read' do
    expect(described_class.new(payload: 'not-a-pix-code', amount_cents: 50_000).perform).to eq('not-a-pix-code')
  end

  it 'has nothing to build without a configured code' do
    expect(described_class.new(payload: nil, amount_cents: 50_000).perform).to be_blank
  end
end
