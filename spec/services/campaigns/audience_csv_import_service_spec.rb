require 'rails_helper'

RSpec.describe Campaigns::AudienceCsvImportService do
  let(:account) { create(:account) }

  def csv_file(content)
    StringIO.new(content)
  end

  def import(content)
    described_class.new(account: account, file: csv_file(content)).perform
  end

  describe '#perform' do
    it 'creates the contacts listed in the file' do
      result = import("id,name,email,phone_number\n1,Maria,maria@exemplo.com,+5511987654321\n")

      contact = account.contacts.find(result[:contact_ids].first)
      expect(contact).to have_attributes(name: 'Maria', email: 'maria@exemplo.com', phone_number: '+5511987654321')
      expect(result).to include(created_count: 1, reused_count: 0)
    end

    # The operator only ever sees this reason in the UI, so it has to name the
    # actual reason a row was dropped — a bare count leaves them guessing which
    # line to fix. Seen with a spreadsheet whose e-mail already belonged to a
    # different contact of the same account.
    it 'reports why a row could not become a contact' do
      create(:contact, account: account, email: 'repetido@exemplo.com', phone_number: '+5511900000001')

      result = import("id,name,email,phone_number\n1,Novo,repetido@exemplo.com,+5511900000002\n")

      expect(result[:created_count]).to eq(0)
      expect(result[:invalid_rows].first[:line]).to eq(2)
      expect(result[:invalid_rows].first[:reason]).to match(/mail/i)
    end

    # The phone number is the identity key, so re-uploading the same audience
    # must not fan out duplicates.
    it 'reuses a contact that already has the phone number' do
      existing = create(:contact, account: account, phone_number: '+5511987654321')

      result = import("id,name,email,phone_number\n1,Nome Diferente,,+5511987654321\n")

      expect(result[:contact_ids]).to eq([existing.id])
      expect(result).to include(created_count: 0, reused_count: 1)
    end

    # A contact created from an inbound message carries the number as its name;
    # the spreadsheet knows who that is.
    it 'names a reused contact whose name is just the phone number' do
      existing = create(:contact, account: account, name: '+5511987654321', phone_number: '+5511987654321', email: nil)

      import("id,name,email,phone_number\n1,Gustavo,gustavo@exemplo.com,+5511987654321\n")

      expect(existing.reload).to have_attributes(name: 'Gustavo', email: 'gustavo@exemplo.com')
    end

    it 'names a reused contact that has no name at all' do
      existing = create(:contact, account: account, name: '', phone_number: '+5511987654321')

      import("id,name,email,phone_number\n1,Gustavo,,+5511987654321\n")

      expect(existing.reload.name).to eq('Gustavo')
    end

    it 'names a reused contact whose name is a single character' do
      existing = create(:contact, account: account, name: 'G', phone_number: '+5511987654321')

      import("id,name,email,phone_number\n1,Gustavo,,+5511987654321\n")

      expect(existing.reload.name).to eq('Gustavo')
    end

    # WhatsApp profile names are often just emoji, which says nothing about who
    # the person is.
    it 'names a reused contact whose name is only emoji' do
      ['👍', '🎉🎉', '👨‍👩‍👧', '🇧🇷', '👍🏽'].each_with_index do |emoji_name, index|
        phone = "+551198765432#{index}"
        existing = create(:contact, account: account, name: emoji_name, phone_number: phone)

        import("id,name,email,phone_number\n1,Gustavo,,#{phone}\n")

        expect(existing.reload.name).to eq('Gustavo')
      end
    end

    # `\p{Emoji}` matches digits too, so a numeric name must not be mistaken
    # for an emoji placeholder — it is still a name someone typed.
    it 'keeps a numeric name that is not the phone number' do
      existing = create(:contact, account: account, name: '2026', phone_number: '+5511987654321')

      import("id,name,email,phone_number\n1,Gustavo,,+5511987654321\n")

      expect(existing.reload.name).to eq('2026')
    end

    # Overwriting a curated name with whatever a campaign spreadsheet carries
    # would let the contact base decay one campaign at a time.
    it 'keeps a real name and a real email that the contact already had' do
      existing = create(:contact, account: account, name: 'Fábio Rocha',
                                  email: 'fabio@empresa.com', phone_number: '+5511987654321')

      import("id,name,email,phone_number\n1,Flamengo,outro@exemplo.com,+5511987654321\n")

      expect(existing.reload).to have_attributes(name: 'Fábio Rocha', email: 'fabio@empresa.com')
    end

    # Spreadsheets hand over numbers with punctuation and no country prefix
    # marker; contacts are stored in E.164.
    it 'normalizes numbers written with punctuation' do
      result = import("id,name,email,phone_number\n1,Maria,,55 (11) 98765-4321\n")

      expect(account.contacts.find(result[:contact_ids].first).phone_number).to eq('+5511987654321')
    end

    it 'reports the rows it could not use instead of failing the whole file' do
      result = import("id,name,email,phone_number\n1,Maria,,+5511987654321\n2,Sem Telefone,,\n")

      expect(result[:contact_ids].size).to eq(1)
      expect(result[:invalid_rows].first).to include(line: 3)
    end

    it 'refuses a file without the required columns' do
      expect { import("id,nome\n1,Maria\n") }
        .to raise_error(described_class::InvalidFile, /phone_number/)
    end

    it 'falls back to the phone number when the row has no name' do
      result = import("id,name,email,phone_number\n1,,,+5511987654321\n")

      expect(account.contacts.find(result[:contact_ids].first).name).to eq('+5511987654321')
    end
  end
end
