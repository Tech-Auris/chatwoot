# The ERP/calendar credentials of each account, moved from the 15 Supabase
# `integration_<erp>` tables into one: a row per account and ERP, with that
# table's columns, under the same names, in `config`. Also adds the Asa Saúde
# ERP (17), which n8n already uses but Rails didn't have.
class CreateAccountIntegrations < ActiveRecord::Migration[7.1]
  def up
    create_table :account_integrations do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :erp_source, null: false, foreign_key: true
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
    add_index :account_integrations, %i[account_id erp_source_id], unique: true

    now = connection.quote(Time.current)
    execute("INSERT INTO erp_sources (id, name, active, created_at, updated_at) VALUES (17, 'Asa Saúde', true, #{now}, #{now}) " \
            'ON CONFLICT DO NOTHING')
  end

  def down
    drop_table :account_integrations
  end
end
