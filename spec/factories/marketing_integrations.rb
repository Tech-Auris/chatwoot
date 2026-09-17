# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_integration do
    account
    provider { :meta_capi }
    status { :test_mode }
    credentials do
      {
        'pixel_id' => '123456789',
        'access_token' => 'EAAG_test_token',
        'test_event_code' => 'TEST12345'
      }
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
