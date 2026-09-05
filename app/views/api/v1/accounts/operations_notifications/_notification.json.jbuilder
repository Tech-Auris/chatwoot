notification, ack, terms_context = pair

json.id notification.id
json.title notification.title
json.body notification.body
json.severity notification.severity
json.trigger_kind notification.trigger_kind
json.scope_type notification.scope_type
json.audience_type notification.audience_type
json.published_at notification.published_at&.to_i
json.expires_at notification.expires_at&.to_i
json.acknowledged_at ack&.acknowledged_at&.to_i

json.subject_type notification.subject_type

# For a re-signature campaign the modal renders the terms body inline
# (scroll → checkbox → sign) instead of the generic "Entendi" button. The
# acceptance token belongs to the current user; the version is pinned to
# the campaign.
if terms_context.present?
  json.terms_acceptance do
    json.token terms_context[:acceptance].request_token
    json.status terms_context[:acceptance].status
    json.deadline_at terms_context[:acceptance].deadline_at&.to_i
  end

  json.terms_version do
    json.id terms_context[:version].id
    json.content terms_context[:version].content
    json.document_date terms_context[:version].document_date&.iso8601
    json.source_url terms_context[:version].source_url
  end
end
