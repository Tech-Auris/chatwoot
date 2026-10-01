FactoryBot.define do
  factory :secretary_version do
    sequence(:name) { |n| "v3.#{n}" }
    sequence(:webhook_url) { |n| "https://n8n.example.com/webhook/secretary-#{n}" }
    status { :active }
  end
end
