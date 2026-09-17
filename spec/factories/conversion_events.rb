# frozen_string_literal: true

FactoryBot.define do
  factory :conversion_event do
    account
    sequence(:name) { |n| "Conversao_#{n}" }
    trigger_type { :automation_action }
    trigger_config { {} }
    meta_event_name { 'Lead' }
    google_event_name { nil }
    enabled { true }

    trait :funnel_stage_reached do
      trigger_type { :funnel_stage_reached }
      trigger_config { { 'funnel_stage_id' => 42 } }
    end

    trait :label_added do
      trigger_type { :label_added }
      trigger_config { { 'label' => 'converteu' } }
    end
  end
end
