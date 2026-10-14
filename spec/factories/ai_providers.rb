FactoryBot.define do
  factory :ai_provider do
    sequence(:name) { |n| "Provider #{n}" }
    sequence(:key) { |n| "provider_#{n}" }
  end
end
