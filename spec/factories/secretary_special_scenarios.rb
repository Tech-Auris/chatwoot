FactoryBot.define do
  factory :secretary_special_scenario do
    account
    sequence(:name) { |n| "cenario_#{n}" }
    situacao { 'Paciente pede reembolso' }
    gatilho { 'reembolso, nota fiscal' }
    instrucao { 'Explique que o reembolso é feito pelo convênio.' }
  end
end
