json.payload do
  json.partial! 'api/v1/accounts/pipelines/pipeline', formats: [:json], pipeline: @pipeline
end
