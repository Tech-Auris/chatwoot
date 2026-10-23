json.payload do
  json.array! @contacts do |contact|
    json.id contact.id
    json.name contact.name
    json.phone_number contact.phone_number
    json.email contact.email
  end
end
json.meta do
  json.current_page @contacts.current_page
  json.total_pages @contacts.total_pages
  json.total_count @contacts.total_count
end
