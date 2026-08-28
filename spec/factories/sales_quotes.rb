FactoryBot.define do
  factory :sales_quote do
    association :seller, factory: :user
    sequence(:clickup_task_id) { |n| "86ak7rd#{n}" }
    prospect_name { 'Clínica Exemplo' }
    prospect_phone { '+5561981402211' }
    status { :draft }
  end

  factory :sales_quote_item do
    sales_quote
    sequence(:stripe_price_id) { |n| "price_#{n}" }
    name { 'Plano Pro' }
    unit_amount { 89_700 }
    quantity { 1 }
  end

  factory :sales_quote_event do
    sales_quote
    event { 'created' }
  end
end

FactoryBot.define do
  factory :pix_renewal do
    account
    sales_quote
    due_on { 10.days.from_now.to_date }
    amount { 89_700 }
    status { :pending }
  end
end
