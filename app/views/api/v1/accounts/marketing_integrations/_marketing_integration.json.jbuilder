# Sensitive fields (access_token, developer_token, oauth_refresh_token) are
# always masked on the way out — the operator saw them when they typed them
# in, and the server never needs to echo them back verbatim. `credentials_set`
# says which keys have a value stored so the UI can show "••••" instead of
# an empty input.
secret_keys = %w[access_token developer_token oauth_refresh_token]

json.id integration.id
json.provider integration.provider
json.status integration.status
json.created_at integration.created_at.to_i
json.updated_at integration.updated_at.to_i
json.credentials do
  integration.credentials.each do |key, value|
    json.set! key, secret_keys.include?(key) ? nil : value
  end
end
json.credentials_set do
  integration.credentials.each do |key, value|
    json.set! key, value.to_s.present?
  end
end
