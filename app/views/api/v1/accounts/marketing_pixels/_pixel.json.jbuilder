# The access token never goes back to the browser; `access_token_set` lets
# the form show "••••" instead of an empty input.
json.id pixel.id
json.name pixel.name
json.pixel_id pixel.pixel_id
json.test_event_code pixel.test_event_code
json.status pixel.status
json.access_token_set pixel.access_token.present?
json.created_at pixel.created_at.to_i
