FactoryBot.define do
  factory :terms_version do
    source_url { 'https://agenteauris.com.br/termos-de-uso/' }
    sequence(:content) { |n| "Termos de uso versão #{n}" }
    fetched_at { Time.current }
  end

  factory :terms_acceptance do
    terms_version
    status { :pending }
  end
end
