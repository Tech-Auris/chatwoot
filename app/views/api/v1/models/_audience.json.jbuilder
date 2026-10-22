json.id resource.id
json.name resource.name
json.kind resource.kind
json.source resource.source
json.rule resource.rule
json.exclusion resource.exclusion
json.window resource.window
json.contacts_count resource.contacts_count
json.counted_at resource.counted_at&.to_i
json.over_limit resource.contacts_count > Audience::MAX_CONTACTS
json.created_at resource.created_at.to_i
json.created_by do
  json.id resource.created_by&.id
  json.name resource.created_by&.name
end
