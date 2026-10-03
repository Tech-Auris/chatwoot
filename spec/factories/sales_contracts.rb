FactoryBot.define do
  factory :sales_contract do
    sales_quote
    sales_contract_template { SalesContractTemplate.current }
    status { :awaiting_signature }
    person_type { 'pj' }
    payment_method { 'card' }
    installments { 12 }
    sequence(:autentique_document_id) { |n| "doc-#{n}" }
    signing_url { 'https://assina.ae/abc' }
    data do
      { 'person_type' => 'pj', 'razao_social' => 'Clínica Cinco Ltda', 'cnpj' => '11.222.333/0001-81', 'nome' => 'Maria Souza',
        'cpf' => '529.982.247-25', 'email' => 'maria@clinica.com.br', 'whatsapp' => '61981402211',
        'endereco' => 'Rua A, 1, Centro, Brasília/DF, CEP 70000-000' }
    end
  end
end
