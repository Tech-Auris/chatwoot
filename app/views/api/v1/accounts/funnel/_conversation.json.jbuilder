# `loss_reason` is passed in from the controller as an already-resolved
# LossReason (or nil) — the board hydrates it in a single batched query
# for every card on screen, so this partial no longer runs a per-card
# `funnel_stage_changes` lookup. The fallback keeps the partial callable
# from paths that render one conversation at a time.
loss_reason = local_assigns.fetch(:loss_reason, nil)
contact = conversation.contact
inbox = conversation.inbox
labels = conversation.cached_label_list_array
funnel_stage = conversation.funnel_stage
if loss_reason.nil? && funnel_stage&.requires_loss_reason? && !local_assigns.key?(:loss_reason)
  latest_change = conversation.account.funnel_stage_changes
                              .where(conversation_id: conversation.id, new_stage: funnel_stage.name)
                              .order(created_at: :desc)
                              .first
  loss_reason = latest_change&.loss_reason
end

json.id conversation.display_id
json.uuid conversation.uuid
json.status conversation.status
json.summary conversation.summary
json.created_at conversation.created_at.to_i
json.last_activity_at conversation.last_activity_at.to_i
json.labels labels
json.ai_enabled conversation.ai_status_enabled?
json.loss_reason loss_reason ? { id: loss_reason.id, name: loss_reason.name } : nil
json.contact do
  json.id contact.id
  json.name contact.name
  json.phone_number contact.phone_number
  json.thumbnail contact.avatar_url
end
json.inbox do
  json.id inbox.id
  json.name inbox.name
  json.channel_type inbox.channel_type
end
