json.payload do
  json.array! @events do |event|
    json.partial! 'conversion_event', event: event
  end
end
