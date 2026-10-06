json.id webhook.id
json.name webhook.name
json.url webhook.url
json.account_id webhook.account_id
json.subscriptions webhook.subscriptions
json.secret webhook.secret
json.inbox_ids webhook.inbox_ids
json.inboxes webhook.inboxes do |inbox|
  json.id inbox.id
  json.name inbox.name
  json.channel_type inbox.channel_type
end
# Single-inbox shape kept for API clients written before multiple inboxes.
if webhook.inbox_ids.size == 1 && (inbox = webhook.inboxes.first)
  json.inbox do
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
  end
end
