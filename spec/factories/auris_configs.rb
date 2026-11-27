FactoryBot.define do
  factory :auris_config do
    sequence(:config_key) { |n| "GDrive.Key#{n}" }
    value_type { 'string' }
    default_value { '1' }
  end

  factory :account_auris_config do
    account
    auris_config
    value { 'folder-1' }
  end
end
