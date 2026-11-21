json.payload do
  json.array! @entries do |entry|
    json.partial! 'api/v1/accounts/pipeline_entries/entry', formats: [:json], entry: entry
    json.pipeline_name entry.pipeline.name
    json.stage do
      json.partial! 'api/v1/accounts/pipelines/stages/stage', formats: [:json], stage: entry.stage
    end
  end
end
