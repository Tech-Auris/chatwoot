FactoryBot.define do
  factory :appointment do
    account
    conversation { association :conversation, account: account }
    contact { conversation.contact }
    status { :scheduled }
  end
end
