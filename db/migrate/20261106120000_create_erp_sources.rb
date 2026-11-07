# The ERPs (and calendars) clinics schedule in, mirrored from the Supabase
# `integration_type` table with the same ids, so n8n can send the same number to
# both sides. Each account points at the one its clinic uses, filled from the
# Supabase `cliente.integration_type` by `rake accounts:import_erp`.
class CreateErpSources < ActiveRecord::Migration[7.1]
  ERP_SOURCES = {
    1 => 'Google Calendar', 2 => 'Feegow', 3 => 'Clínica Ágil', 4 => 'Saude Agora', 5 => 'MedWare', 6 => 'CliniCorp',
    7 => 'VisualASA CIG', 8 => 'MedX', 9 => 'Prodoctor Arco Hospital', 10 => 'Amplimed', 11 => 'Amigo', 12 => 'Gester',
    13 => 'Klingo', 14 => 'Prontuario Verde', 15 => 'VisualASA Geral', 16 => 'TI Saude'
  }.freeze

  def up
    create_table :erp_sources do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :erp_sources, :name, unique: true

    add_reference :accounts, :erp_source, foreign_key: true

    seed_erp_sources
  end

  def down
    remove_reference :accounts, :erp_source, foreign_key: true
    drop_table :erp_sources
  end

  private

  def seed_erp_sources
    now = connection.quote(Time.current)
    values = ERP_SOURCES.map { |id, name| "(#{id}, #{connection.quote(name)}, true, #{now}, #{now})" }.join(', ')
    execute("INSERT INTO erp_sources (id, name, active, created_at, updated_at) VALUES #{values} ON CONFLICT (id) DO NOTHING")
  end
end
