json.payload do
  json.partial! 'api/v1/models/audience', formats: [:json], resource: @audience
  json.ignored_conditions @ignored_conditions if @ignored_conditions
  json.invalid_rows @invalid_rows if @invalid_rows
  if @events
    json.events @events do |event|
      json.id event.id
      json.kind event.kind
      json.contacts_count event.contacts_count
      json.format event.format
      json.user_name event.user&.name
      json.campaign_title event.campaign&.title
      json.created_at event.created_at.to_i
    end
  end
end
