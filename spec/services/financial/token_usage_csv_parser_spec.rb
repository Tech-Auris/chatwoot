require 'rails_helper'

RSpec.describe Financial::TokenUsageCsvParser do
  def parse(content)
    described_class.new(file: StringIO.new(content)).parse
  end

  # The header of the export the finance team already generates.
  let(:header) { "accountid,accountname,texto,imagem arquivo e transcrições,audio\n" }

  it 'reads the columns of the usage export' do
    rows = parse("#{header}46,Leger,83601,3147,0\n")

    expect(rows).to eq([{ account_id: 46, account_name: 'Leger', text: 83_601, media: 3147, audio: 0 }])
  end

  # "1.480" is how a spreadsheet prints a thousand — `to_i` would read it as 1
  # and bill the customer for a single message.
  it 'reads a quantity formatted with a thousands separator' do
    rows = parse("#{header}16,SaquaMed,\"7.038\",\"227\",\"140\"\n")

    expect(rows.first).to include(text: 7038, media: 227, audio: 140)
  end

  it 'accepts the semicolon export as well' do
    rows = parse("accountid;accountname;texto;imagem arquivo e transcrições;audio\n21;Reis Odontologia;3154;72;347\n")

    expect(rows.first).to include(account_id: 21, text: 3154, audio: 347)
  end

  # Accents and spacing drift between exports; none of that should force
  # someone to edit the file before importing.
  it 'matches the columns regardless of accents, case and spacing' do
    rows = parse("AccountID,Account Name,TEXTO,Imagem Arquivo e Transcricoes,Audio\n9,Unicordis,50,0,0\n")

    expect(rows.first).to include(account_id: 9, text: 50)
  end

  it 'ignores rows without an account id, like the total line' do
    rows = parse("#{header}1,Auris,600,6,32\n,TOTAL,600,6,32\n")

    expect(rows.length).to eq(1)
  end

  it 'refuses a file missing a quantity column' do
    expect { parse("accountid,accountname,texto\n1,Auris,600\n") }
      .to raise_error(described_class::InvalidFile, /imagem|media/i)
  end

  it 'refuses a file that is not a spreadsheet at all' do
    expect { parse("isso não é um csv\"\n") }.to raise_error(described_class::InvalidFile)
  end
end
