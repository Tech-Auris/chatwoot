FactoryBot.define do
  factory :secretary_prompt do
    core_behavior { 'Seja cordial.' }
    communication_rules { 'Mensagens curtas.' }
    medical_compliance { 'Não dê diagnósticos.' }
    tools_usage { 'Use a agenda antes de confirmar horários.' }
  end
end
