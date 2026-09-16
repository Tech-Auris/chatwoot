require 'rails_helper'

RSpec.describe BrDocumentChecksum do
  describe '.valid_cpf?' do
    it 'accepts a valid CPF with punctuation' do
      expect(described_class.valid_cpf?('529.982.247-25')).to be(true)
    end

    it 'accepts a valid CPF without punctuation' do
      expect(described_class.valid_cpf?('52998224725')).to be(true)
    end

    # The one the bug report brought in: 11 digits with a wrong check digit.
    it 'refuses a CPF whose check digits do not match' do
      expect(described_class.valid_cpf?('12345678900')).to be(false)
    end

    it 'refuses a CPF with the wrong number of digits' do
      expect(described_class.valid_cpf?('529982247')).to be(false)
      expect(described_class.valid_cpf?('5299822472555')).to be(false)
    end

    # Sequences that satisfy the arithmetic by chance — Receita does not
    # issue them, so we do not accept them either.
    it 'refuses an all-same-digit CPF' do
      expect(described_class.valid_cpf?('00000000000')).to be(false)
      expect(described_class.valid_cpf?('11111111111')).to be(false)
    end

    it 'refuses a blank or nil value' do
      expect(described_class.valid_cpf?(nil)).to be(false)
      expect(described_class.valid_cpf?('')).to be(false)
    end
  end

  describe '.valid_cnpj?' do
    it 'accepts a valid CNPJ with punctuation' do
      expect(described_class.valid_cnpj?('11.222.333/0001-81')).to be(true)
    end

    it 'accepts a valid CNPJ without punctuation' do
      expect(described_class.valid_cnpj?('11222333000181')).to be(true)
    end

    # The one the bug report brought in: 13 digits (one short) with a value
    # that used to reach Stripe as a `br_cnpj` and get rejected there.
    it 'refuses a 13-digit CNPJ' do
      expect(described_class.valid_cnpj?('0872224900012')).to be(false)
    end

    it 'refuses a CNPJ whose check digits do not match' do
      expect(described_class.valid_cnpj?('12345678000190')).to be(false)
    end

    it 'refuses an all-same-digit CNPJ' do
      expect(described_class.valid_cnpj?('00000000000000')).to be(false)
    end

    it 'refuses a blank or nil value' do
      expect(described_class.valid_cnpj?(nil)).to be(false)
      expect(described_class.valid_cnpj?('')).to be(false)
    end
  end
end
