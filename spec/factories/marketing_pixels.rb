# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_pixel do
    marketing_integration
    account { marketing_integration.account }
    sequence(:name) { |n| "Pixel #{n}" }
    sequence(:pixel_id) { |n| "12345678#{n}" }
    access_token { 'EAAG_test_token' }
    test_event_code { 'TEST12345' }
    status { :test_mode }
  end
end
