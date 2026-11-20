FactoryBot.define do
  factory :account_integration do
    account
    erp_source
    config { { 'access_token' => 'tok-1234567890', 'local_id' => '1' } }
  end
end
