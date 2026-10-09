FactoryBot.define do
  factory :follow_up do
    conversation
    account { conversation.account }
    inbox { conversation.inbox }
    run_id { '1785283326516' }
    step { 1 }
    delay_minutes { 240 }
  end
end
