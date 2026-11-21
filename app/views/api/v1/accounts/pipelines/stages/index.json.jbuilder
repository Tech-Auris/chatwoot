json.payload do
  json.array! @stages do |stage|
    json.partial! 'api/v1/accounts/pipelines/stages/stage', formats: [:json], stage: stage
  end
end
