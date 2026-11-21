json.payload do
  json.entries @entries do |entry|
    json.partial! 'api/v1/accounts/pipeline_entries/entry', formats: [:json], entry: entry
  end
  json.meta do
    json.total @total
    json.has_more @has_more
  end
end
