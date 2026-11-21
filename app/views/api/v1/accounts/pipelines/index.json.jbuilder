json.payload do
  json.array! @pipelines do |pipeline|
    json.partial! 'api/v1/accounts/pipelines/pipeline', formats: [:json], pipeline: pipeline
    json.entries_count @open_counts[pipeline.id] || 0
  end
end
