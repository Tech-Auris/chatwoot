FactoryBot.define do
  factory :account_status do
    status { :payment_pending }
    label { 'Sem pagamento' }
    name { 'SEM_PAGAMENTO' }
    send_private_message { true }
    private_message { 'Ainda não identificamos o seu pagamento.' }
    message_cooldown_minutes { 60 }
  end
end
