# A plain array, like the Postgres node returned. `id` and `inbox_id` go as
# strings, as the bigints came from Postgres; `cliente_id` is the account id.
json.array! @secretary_confirmations do |confirmation|
  json.id confirmation.id.to_s
  json.calendar_id confirmation.calendar_id
  json.chatwoot_account_id confirmation.account_id
  json.message confirmation.message
  json.message_48h confirmation.message_48h
  json.message_2h confirmation.message_2h
  json.message_30m confirmation.message_30m
  json.message_hj confirmation.message_hj
  json.versao_workflow confirmation.versao_workflow
  json.inbox_id confirmation.inbox_id
  json.message_72h confirmation.message_72h
  json.unidade_id confirmation.unidade_id
  json.message_96h confirmation.message_96h
  json.cliente_id confirmation.account_id
end
