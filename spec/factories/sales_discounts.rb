FactoryBot.define do
  factory :sales_discount do
    name { 'Indicação' }
    percent { 5 }
    stripe_product_ids { [] }
    expires_with_reservation { false }
    active { true }
  end
end
