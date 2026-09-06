FactoryBot.define do
  factory :terms_version do
    source_url { 'https://www.auris.ia.br/termos-de-uso' }
    sequence(:content) { |n| "Termos de uso versão #{n}" }
    fetched_at { Time.current }
    document_date { Date.new(2026, 9, 3) }
  end

  factory :terms_acceptance do
    terms_version
    status { :pending }
    kind { :signature }
  end

  factory :terms_acceptance_request do
    terms_version
    association :created_by, factory: :super_admin
    kind { :update }
    document_date { Date.new(2026, 9, 3) }
    deadline_at { 7.days.from_now.change(usec: 0) }
  end
end
