json.partial! 'activity_log', activity_log: @activity_log
json.audited_changes @activity_log.audited_changes
json.request_id @activity_log.request_id
json.history do
  json.array! @history, partial: 'activity_log', as: :activity_log
end
