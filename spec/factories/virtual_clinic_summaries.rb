FactoryBot.define do
  factory :virtual_clinic_summary do
    account
    user
    daily { true }
    hour { 8 }
  end
end
