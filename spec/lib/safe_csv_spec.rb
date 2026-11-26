require 'rails_helper'

describe SafeCsv do
  def line(*fields)
    described_class.generate_line(fields).chomp
  end

  it 'prefixes cells a spreadsheet would run as a formula' do
    expect(CSV.parse_line(line('=HYPERLINK("http://x","y")', '@SUM(1)', '-1+2', '+1+2'))).to eq(
      ["'=HYPERLINK(\"http://x\",\"y\")", "'@SUM(1)", "'-1+2", "'+1+2"]
    )
  end

  it 'keeps E.164 phone numbers, numbers and plain text as they are' do
    expect(CSV.parse_line(line('+5511999999999', 42, nil, 'Ana & Bia'))).to eq(['+5511999999999', '42', nil, 'Ana & Bia'])
  end
end
