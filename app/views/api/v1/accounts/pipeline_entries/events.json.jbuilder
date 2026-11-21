json.payload do
  json.array! @events do |event|
    json.id event.id
    json.from_stage event.from_stage&.slice(:id, :name, :color)
    json.to_stage event.to_stage&.slice(:id, :name, :color)
    json.user event.user&.slice(:id, :name)
    json.source event.source
    json.reason event.reason
    json.loss_reason event.loss_reason&.slice(:id, :name)
    json.created_at event.created_at.to_i
  end
end
