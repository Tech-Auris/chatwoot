json.payload @appointments do |appointment|
  json.id appointment.id
  json.source_id appointment.erp_source_id
  json.source_name appointment.erp_source&.name
  json.external_id appointment.external_id
  json.status appointment.status
  json.scheduled_for appointment.scheduled_for&.iso8601
  json.attended_at appointment.attended_at&.iso8601
  json.professional do
    json.id appointment.professional_external_id
    json.name appointment.professional_name
  end
  json.procedure do
    json.id appointment.procedure_external_id
    json.name appointment.procedure_name
  end
  json.procedures appointment.procedures do |procedure|
    json.id procedure.procedure_external_id
    json.name procedure.procedure_name
    json.amount_paid procedure.amount_paid_cents && (procedure.amount_paid_cents / 100.0)
  end
end
