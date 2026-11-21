latest_conversation = @latest_conversations[entry.contact_id]
json.id entry.id
json.pipeline_id entry.pipeline_id
json.pipeline_stage_id entry.pipeline_stage_id
json.stage_entered_at entry.stage_entered_at.to_i
json.created_at entry.created_at.to_i
json.closed_at entry.closed_at&.to_i
json.source entry.source
json.origin_type entry.origin_type
json.added_by entry.added_by&.slice(:id, :name)
json.loss_reason entry.loss_reason&.slice(:id, :name)
json.contact do
  json.id entry.contact.id
  json.name entry.contact.name
  json.phone_number entry.contact.phone_number
  json.thumbnail entry.contact.avatar_url
end
json.latest_conversation latest_conversation && { id: latest_conversation.display_id, status: latest_conversation.status }
