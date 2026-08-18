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

    # The phone number is the identity key, so re-uploading the same audience
    # must not fan out duplicates.
    it 'reuses a contact that already has the phone number' do
      existing = create(:contact, account: account, phone_number: '+5511987654321')

      result = import("id,name,email,phone_number\n1,Nome Diferente,,+5511987654321\n")

      expect(result[:contact_ids]).to eq([existing.id])
      expect(result).to include(created_count: 0, reused_count: 1)
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
