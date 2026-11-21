FactoryBot.define do
  factory :pipeline do
    account
    sequence(:name) { |n| "Pipeline #{n}" }

    after(:create) do |pipeline|
      pipeline.stages.create!(name: 'Acompanhamento', color: '#3b82f6')
      pipeline.stages.create!(name: 'Retorno', color: '#10b981')
      pipeline.stages.reset
    end
  end

  factory :pipeline_entry do
    pipeline
    account { pipeline.account }
    contact { association :contact, account: pipeline.account }
    stage { pipeline.first_open_stage }
    stage_entered_at { Time.current }
  end
end
