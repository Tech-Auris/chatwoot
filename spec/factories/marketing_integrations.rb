# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_integration do
    account
    provider { :meta_capi }
    status { :active }
    credentials { {} }

    # The pixels conversions go to live on their own rows now.
    trait :with_pixel do
      after(:create) { |integration| create(:marketing_pixel, marketing_integration: integration) }
    end

    trait :google_ads do
      provider { :google_ads_enhanced }
      credentials do
        {
          'customer_id' => '1234567890',
          'conversion_action_id' => '9876543210',
          'developer_token' => 'DEV_TOKEN',
          'oauth_refresh_token' => '1//refresh_token'
        }
      end
    end
  end
end
