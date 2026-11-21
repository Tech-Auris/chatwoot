json.payload do
  json.partial! 'api/v1/accounts/pipelines/stages/stage', formats: [:json], stage: @stage
end
