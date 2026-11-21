json.payload do
  json.partial! 'api/v1/accounts/pipeline_entries/entry', formats: [:json], entry: @entry
end
