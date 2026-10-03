require 'rails_helper'

RSpec.describe Sales::ContractForm do
  let(:attributes) do
    { person_type: 'pj', razao_social: 'Clínica Cinco Ltda', cnpj: '11.222.333/0001-81', nome: 'Maria Souza', cpf: '529.982.247-25',
      email: 'maria@clinica.com.br', whatsapp: '61981402211', cep: '70000000', logradouro: 'Rua A', numero: '1', complemento: '',
      bairro: 'Centro', cidade: 'Brasília', uf: 'DF', payment_method: 'card' }
  end

  it 'accepts a complete company form and writes the address in one line' do
    form = described_class.new(attributes)

    expect(form).to be_valid
    expect(form.data['endereco']).to eq('Rua A, 1, Centro, Brasília/DF, CEP 70000-000')
  end

  it 'formats the documents however they were typed' do
    data = described_class.new(attributes.merge(cnpj: '11222333000181', cpf: '52998224725')).data

    expect(data).to include('cnpj' => '11.222.333/0001-81', 'cpf' => '529.982.247-25')
  end

  it 'refuses an invalid CNPJ and CPF, in Portuguese' do
    form = described_class.new(attributes.merge(cnpj: '11.111.111/1111-11', cpf: '111.111.111-11'))

    form.validate
    expect(form.errors.full_messages).to include('CNPJ inválido', 'CPF inválido')
  end

  it 'does not ask for the company data from a person' do
    form = described_class.new(attributes.merge(person_type: 'pf', razao_social: '', cnpj: ''))

    expect(form).to be_valid
    expect(form.data.keys).not_to include('razao_social', 'cnpj')
  end
end
