json.payload do
  json.array! @audiences do |audience|
    json.partial! 'api/v1/models/audience', formats: [:json], resource: audience
  end
end
