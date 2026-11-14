FactoryBot.define do
  factory :secretary_resource do
    account
    sequence(:key) { |n| "recurso_#{n}" }
    resource_url { 'https://example.supabase.co/storage/v1/object/public/resources/file.png' }
    caption { 'Segue o arquivo' }
    secretary_resource_type { SecretaryResourceType.find_or_create_by!(id: 1) { |type| type.description = 'image' } }
  end
end
