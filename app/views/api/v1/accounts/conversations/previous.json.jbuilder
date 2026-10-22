json.first_message_id @first_message_id
if @previous_conversation
  json.payload do
    json.id @previous_conversation.display_id
    json.created_at @previous_conversation.created_at.to_i
    json.status @previous_conversation.status
    json.inbox_name @previous_conversation.inbox.name
    json.messages_count @previous_conversation.messages.where(message_type: %i[incoming outgoing]).count
    json.has_previous @has_previous
  end
else
  json.payload nil
end
