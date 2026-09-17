class CreateConversionEvents < ActiveRecord::Migration[7.1]
  # Mapping of a Chatwoot trigger (funnel_stage reached, label added,
  # automation action) to a Meta CAPI and/or Google Ads event name.
  # `trigger_config` (jsonb) holds the trigger-specific data: for
  # `funnel_stage_reached` it's `{ "funnel_stage_id": 42 }`, for `label_added`
  # it's `{ "label": "converteu" }`, and for `automation_action` it's `{}`
  # (the action selects the event by id at runtime).
  #
  # `meta_event_name` and `google_event_name` are optional so a clinic can
  # send only to one provider; leaving both nil disables the event
  # effectively even when `enabled=true`.
  def change
    create_table :conversion_events do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.integer :trigger_type, null: false
      t.jsonb :trigger_config, null: false, default: {}
      t.string :meta_event_name
      t.string :google_event_name
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :conversion_events, %i[account_id trigger_type]
    add_index :conversion_events, %i[account_id enabled]
  end
end
