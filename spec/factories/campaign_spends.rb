# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_spend do
    account
    provider { :meta }
    sequence(:source_id) { |n| "ad_#{n}" }
    source_type { 'meta_ad' }
    period_start { Date.current }
    period_end { Date.current }
    amount_cents { 5000 }
    currency { 'BRL' }
    last_synced_at { Time.current }
    external_metadata { {} }

    trait :google do
      provider { :google_ads }
      source_type { 'google_ads_campaign' }
      sequence(:source_id) { |n| "gads_#{n}" }
    end
  end
end
