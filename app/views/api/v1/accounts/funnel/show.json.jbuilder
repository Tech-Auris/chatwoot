json.payload do
  json.stages do
    json.array! @stages do |stage|
      conversations = @conversations_by_stage[stage.id] || []
      total = @stage_totals[stage.id] || 0
      json.id stage.id
      json.name stage.name
      json.description stage.description
      json.position stage.position
      json.closed stage.closed
      json.color stage.color
      json.requires_loss_reason stage.requires_loss_reason
      json.conversations do
        json.array!(conversations) do |conversation|
          json.partial! 'api/v1/accounts/funnel/conversation', formats: [:json],
                                                               conversation: conversation,
                                                               loss_reason: @loss_reasons_by_conversation_id[conversation.id]
        end
      end
      json.count total
      json.has_more conversations.size < total
      json.loaded_count conversations.size
    end
  end
end
