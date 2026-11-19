FactoryBot.define do
  factory :account_prompt do
    account
    name { 'Geral' }
    ai_prompt_system_message { 'Você é a secretária da Clínica Exemplo.' }
    inbox_ids { [] }

    # A specific prompt needs the account's general one, created here if missing.
    trait :specific do
      name { 'Específico 1' }
      inbox_ids { [create(:inbox, account: account).id] }

      after(:build) do |prompt|
        create(:account_prompt, account: prompt.account) unless prompt.account.account_prompts.general.exists?
      end
    end
  end
end
