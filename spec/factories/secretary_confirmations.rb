FactoryBot.define do
  factory :secretary_confirmation do
    account
    versao_workflow { '5.1' }
    calendar_id { 'clinica@group.calendar.google.com' }
    message { 'Olá {{nome}}, confirma sua consulta {{dia}} às {{hora}}?' }
    message_2h { '' }
  end

  factory :secretary_confirmation_send_log do
    account
    sequence(:event_id) { |n| "evento_#{n}" }
    calendar_id { 'clinica@group.calendar.google.com' }
    reminder_type { '24h' }
  end
end
