json.enabled @inbox.ai_schedule_enabled
json.team_id @inbox.ai_schedule_team_id
json.secretary_enabled @inbox.secretary_enabled
json.timezone @inbox.timezone
json.hours @inbox.ai_off_hours do |hour|
  json.day_of_week hour.day_of_week
  json.from format('%<h>02d:%<m>02d', h: hour.from_minutes / 60, m: hour.from_minutes % 60)
  json.to format('%<h>02d:%<m>02d', h: hour.to_minutes / 60, m: hour.to_minutes % 60)
end
