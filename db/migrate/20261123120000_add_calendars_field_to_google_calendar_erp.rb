# ERP → Agenda reads a clinic with one Google calendar per professional from a
# `calendars` list in its Google Calendar integration (erp_sources id 1):
# `[{ "calendar_id": "...", "professional": "Dra. Ana" }]`. `calendar_id` stays
# for the clinics with a single calendar, which n8n reads.
class AddCalendarsFieldToGoogleCalendarErp < ActiveRecord::Migration[7.1]
  FIELD = { 'key' => 'calendars', 'label' => 'Agendas por profissional', 'type' => 'json', 'secret' => false }.freeze

  def up
    execute <<~SQL.squish
      UPDATE erp_sources SET fields = fields || #{connection.quote([FIELD].to_json)}::jsonb, updated_at = NOW()
      WHERE id = 1 AND NOT fields @> '[{"key": "calendars"}]'::jsonb
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE erp_sources
      SET fields = COALESCE((SELECT jsonb_agg(field) FROM jsonb_array_elements(fields) field WHERE field->>'key' <> 'calendars'), '[]'::jsonb)
      WHERE id = 1
    SQL
  end
end
