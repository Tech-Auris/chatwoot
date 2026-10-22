json.payload do
  json.array! @contacts do |contact|
    conversation = @latest_conversations[contact.id]
    json.id contact.id
    json.name contact.name
    json.phone_number contact.phone_number
    json.email contact.email
    json.funnel_stage conversation&.funnel_stage&.name
    json.funnel_stage_color conversation&.funnel_stage&.color
    json.labels conversation&.cached_label_list_array || []
    json.inbox_name conversation&.inbox&.name
    json.conversation_id conversation&.display_id
  end
end
json.meta do
  json.current_page @contacts.current_page
  json.total_pages @contacts.total_pages
  json.total_count @contacts.total_count
end
