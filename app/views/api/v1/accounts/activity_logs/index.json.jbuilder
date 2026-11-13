json.payload do
  json.array! @activity_logs, partial: 'activity_log', as: :activity_log
end
json.meta do
  json.count @activity_logs.total_count
  json.current_page @activity_logs.current_page
  json.per_page Api::V1::Accounts::ActivityLogsController::PER_PAGE
  json.auditable_types @auditable_types
end
