json.payload do
  json.array! @integrations do |integration|
    json.partial! 'marketing_integration', integration: integration
  end
end
