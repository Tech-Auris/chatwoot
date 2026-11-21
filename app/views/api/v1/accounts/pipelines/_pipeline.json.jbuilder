json.id pipeline.id
json.name pipeline.name
json.position pipeline.position
json.archived_at pipeline.archived_at&.to_i
json.stages pipeline.stages do |stage|
  json.partial! 'api/v1/accounts/pipelines/stages/stage', formats: [:json], stage: stage
end
