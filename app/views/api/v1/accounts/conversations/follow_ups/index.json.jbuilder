json.payload do
  json.array! @follow_ups do |follow_up|
    json.partial! 'api/v1/models/follow_up', follow_up: follow_up
  end
end
