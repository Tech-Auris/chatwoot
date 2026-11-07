json.payload do
  json.array! @erp_sources do |erp_source|
    json.id erp_source.id
    json.name erp_source.name
  end
end
