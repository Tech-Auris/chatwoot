FactoryBot.define do
  factory :erp_source do
    # The id is always given (the Supabase integration_type id), never generated.
    sequence(:id) { |n| 1000 + n } # rubocop:disable FactoryBot/IdSequence
    sequence(:name) { |n| "ERP #{n}" }
    active { true }
  end
end
