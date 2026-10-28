# Hours in which the AI secretary is off in an inbox: a patient message then
# hands the conversation to the inbox's team. Several ranges per weekday.
class CreateInboxAiOffHours < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :ai_schedule_enabled, :boolean, default: false, null: false
    add_reference :inboxes, :ai_schedule_team, foreign_key: { to_table: :teams, on_delete: :nullify }, null: true

    create_table :inbox_ai_off_hours do |t|
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.integer :day_of_week, null: false
      t.integer :from_minutes, null: false
      t.integer :to_minutes, null: false
      t.timestamps
    end

    # Why the AI handed the conversation over: by the AI itself, or by the schedule.
    add_column :ai_assignment_attempts, :reason, :integer, default: 0, null: false
  end
end
