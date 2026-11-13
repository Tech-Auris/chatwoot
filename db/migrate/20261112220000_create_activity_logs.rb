class CreateActivityLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :activity_logs do |t|
      t.bigint :account_id, null: false
      t.string :auditable_type, null: false
      t.bigint :auditable_id
      t.string :auditable_label
      t.string :action, null: false
      t.jsonb :audited_changes, null: false, default: {}
      t.string :actor_type, null: false
      t.bigint :actor_id
      t.string :actor_label
      t.string :source, null: false
      t.string :ip_address
      t.string :request_id
      t.datetime :created_at, null: false
    end

    add_index :activity_logs, [:account_id, :created_at]
    add_index :activity_logs, [:auditable_type, :auditable_id]
    add_index :activity_logs, [:actor_type, :actor_id]
  end
end
