FactoryBot.define do
  factory :audience do
    account
    sequence(:name) { |n| "Público #{n}" }
    kind { :dynamic }
    source { 'manual' }
  end
end
