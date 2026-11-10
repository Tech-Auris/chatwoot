class AddAiOffSwitchesToContactsAndInboxes < ActiveRecord::Migration[7.1]
  def change
    change_table :contacts, bulk: true do |t|
      t.boolean :ai_disabled, default: false, null: false
      t.datetime :ai_disabled_at
      t.bigint :ai_disabled_by_id
    end

    add_column :inboxes, :ai_paused, :boolean, default: false, null: false
  end
end
