# Meta rejects the web event names Lead and Schedule for events from a
# conversation, so every one of them failed. Moves them to the names Meta
# accepts there: a new contact is a submitted lead, an appointment a
# qualified one.
class RenameMetaWebEventNamesOnConversionEvents < ActiveRecord::Migration[7.1]
  RENAMES = { 'Lead' => 'LeadSubmitted', 'Schedule' => 'QualifiedLead' }.freeze

  def up
    RENAMES.each do |from, to|
      execute("UPDATE conversion_events SET meta_event_name = #{connection.quote(to)} WHERE meta_event_name = #{connection.quote(from)}")
    end
  end

  def down
    RENAMES.each do |from, to|
      execute("UPDATE conversion_events SET meta_event_name = #{connection.quote(from)} WHERE meta_event_name = #{connection.quote(to)}")
    end
  end
end
