require 'rails_helper'

RSpec.describe Financial::StripeCustomerMatcher do
  def customer(id:, name: nil, email: nil)
    Struct.new(:id, :name, :email).new(id, name, email)
  end

  def account(name)
    Struct.new(:name).new(name)
  end

  describe '#suggestions_for' do
    it 'matches an exact administrator email' do
      customers = [customer(id: 'cus_1', name: 'Clínica São José', email: 'admin@clinicasj.com.br')]

      result = described_class.new(customers).suggestions_for(account('Outro nome'), ['admin@clinicasj.com.br'])

      expect(result.first).to include(id: 'cus_1', reason: 'E-mail do administrador confere')
    end

    it 'ignores case and surrounding spaces on the email' do
      customers = [customer(id: 'cus_1', email: 'Admin@Clinicasj.com.br')]

      result = described_class.new(customers).suggestions_for(account('Clínica'), ['  admin@clinicasj.com.br '])

      expect(result.first[:id]).to eq('cus_1')
    end

    it 'matches the email domain when the person differs' do
      customers = [customer(id: 'cus_1', name: 'Clínica SJ', email: 'financeiro@clinicasj.com.br')]

      result = described_class.new(customers).suggestions_for(account('Outro nome'), ['recepcao@clinicasj.com.br'])

      expect(result.first).to include(id: 'cus_1', reason: 'Mesmo domínio de e-mail')
    end

    # A gmail address says nothing about which company the customer is, so a
    # domain hit there would pair unrelated accounts.
    it 'does not match on generic email providers' do
      customers = [customer(id: 'cus_1', name: 'Outra empresa', email: 'contato@gmail.com')]

      result = described_class.new(customers).suggestions_for(account('Clínica'), ['dono@gmail.com'])

      expect(result).to be_empty
    end

    it 'matches names ignoring accents, case and punctuation' do
      customers = [customer(id: 'cus_1', name: 'Clínica São José Ltda.')]

      result = described_class.new(customers).suggestions_for(account('clinica sao jose ltda'), [])

      expect(result.first).to include(id: 'cus_1', reason: 'Nome parecido')
    end

    it 'ranks the email match above domain and name matches' do
      customers = [
        customer(id: 'cus_name', name: 'Clínica SJ'),
        customer(id: 'cus_domain', name: 'Qualquer', email: 'outro@clinicasj.com.br'),
        customer(id: 'cus_email', name: 'Qualquer', email: 'admin@clinicasj.com.br')
      ]

      result = described_class.new(customers).suggestions_for(account('Clínica SJ'), ['admin@clinicasj.com.br'])

      expect(result.map { |suggestion| suggestion[:id] }).to eq(%w[cus_email cus_domain cus_name])
    end

    it 'returns nothing when no rule hits' do
      customers = [customer(id: 'cus_1', name: 'Empresa X', email: 'contato@empresax.com')]

      result = described_class.new(customers).suggestions_for(account('Clínica SJ'), ['admin@clinicasj.com.br'])

      expect(result).to be_empty
    end

    it 'caps the list so the screen stays readable' do
      customers = Array.new(5) { |i| customer(id: "cus_#{i}", email: "pessoa#{i}@clinicasj.com.br") }

      result = described_class.new(customers).suggestions_for(account('Clínica'), ['admin@clinicasj.com.br'])

      expect(result.size).to eq(described_class::MAX_SUGGESTIONS)
    end

    it 'handles accounts with no administrator email' do
      customers = [customer(id: 'cus_1', name: 'Clínica SJ')]

      result = described_class.new(customers).suggestions_for(account('Clínica SJ'), nil)

      expect(result.first[:id]).to eq('cus_1')
    end

    # A customer with a blank name would otherwise normalize to "" and match
    # every account whose name also normalizes to "".
    it 'does not pair blank names' do
      customers = [customer(id: 'cus_1', name: nil, email: nil)]

      result = described_class.new(customers).suggestions_for(account(''), [])

      expect(result).to be_empty
    end
  end
end
