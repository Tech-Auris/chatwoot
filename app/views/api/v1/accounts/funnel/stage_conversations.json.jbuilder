json.payload do
  json.stage_id @stage.id
  json.conversations do
    json.array!(@conversations) do |conversation|
      json.partial! 'api/v1/accounts/funnel/conversation', formats: [:json],
                                                           conversation: conversation,
                                                           loss_reason: @loss_reasons_by_conversation_id[conversation.id]
    end
  end
  json.meta do
    json.current_page @current_page
    json.per_page @per_page
    json.loaded_count @conversations.size
    json.total @total
    json.has_more @has_more
  end
end
