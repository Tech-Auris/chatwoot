FactoryBot.define do
  factory :erp_source do
    # The id is always given (the Supabase integration_type id), never generated.
    sequence(:id) { |n| 1000 + n } # rubocop:disable FactoryBot/IdSequence
    sequence(:name) { |n| "ERP #{n}" }
    active { true }

    trait :with_fields do
      fields do
        [{ 'key' => 'access_token', 'label' => 'Access token', 'type' => 'text', 'secret' => true },
         { 'key' => 'local_id', 'label' => 'Local ID', 'type' => 'number', 'secret' => false },
         { 'key' => 'token_overrides', 'label' => 'Token overrides', 'type' => 'json', 'secret' => true }]
      end
    end
  end
end
