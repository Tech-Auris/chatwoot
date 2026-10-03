# The values that fill the contract template's `{{campos}}`. `sample` feeds the
# Super Admin preview; the real values come from the reservation and the data
# the customer confirms in the Contrato step.
module Sales::ContractVariables
  FIELDS = %w[razao_social cnpj endereco representante_nome representante_cpf representante_email
              nome_completo cpf email periodo_licenca produtos valor_total valor_total_extenso
              forma_pagamento descontos data_contratacao].freeze

  module_function

  def sample(person_type)
    contractor = if person_type.to_s == 'pf'
                   { nome_completo: 'Ana Maria Souza', cpf: '987.654.321-00', email: 'ana@exemplo.com.br' }
                 else
                   { razao_social: 'Clínica Exemplo Serviços Médicos Ltda.', cnpj: '12.345.678/0001-90',
                     representante_nome: 'Gustavo Fraga', representante_cpf: '123.456.789-09',
                     representante_email: 'gustavo@clinicaexemplo.com.br' }
                 end
    contractor.merge(
      endereco: 'Avenida Paulista, 1000, Conj. 101, Bela Vista, São Paulo/SP, CEP 01310-100',
      periodo_licenca: '12 (doze) meses, de 15/10/2026 a 14/10/2027',
      produtos: '<ul><li>Plano Auris</li><li>Profissional adicional × 2</li></ul>',
      valor_total: '22.190,40',
      valor_total_extenso: Sales::MoneyInWords.call(2_219_040),
      forma_pagamento: "12 (doze) parcelas de R$ 1.849,20 (#{Sales::MoneyInWords.call(184_920)}) no cartão de crédito",
      descontos: '10% de desconto na reunião (R$ 2.465,60)',
      data_contratacao: '15/10/2026'
    )
  end
end
