# Same shape as the Supabase `confirmacoes_send_log` rows.
json.array! @send_logs do |send_log|
  json.id send_log.id
  json.calendar_id send_log.calendar_id
  json.chatwoot_account_id send_log.account_id
  json.event_id send_log.event_id
  json.reminder_type send_log.reminder_type
  json.sent_at send_log.sent_at
end
