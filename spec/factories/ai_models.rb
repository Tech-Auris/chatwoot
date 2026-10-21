FactoryBot.define do
  factory :ai_model do
    ai_provider
    sequence(:name) { |n| "gpt-#{n}" }
    sequence(:key) { |n| "model_#{n}" }
    sequence(:model_id) { |n| "gpt-#{n}" }
    status { :active }
  end
end
