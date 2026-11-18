FactoryBot.define do
  factory :inbox_prompt do
    account
    ai_prompt_system_message { 'Você é a secretária da Clínica Exemplo.' }
    inbox_ids { [create(:inbox, account: account).id] }
  end
end
