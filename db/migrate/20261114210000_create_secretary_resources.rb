class CreateSecretaryResources < ActiveRecord::Migration[7.1]
  # The ids n8n's `1.4. Resource` switch branches on, same as the Supabase `resource_type` table.
  TYPES = { 1 => 'image', 2 => 'pdf', 3 => 'video', 4 => 'audio', 5 => 'macro', 6 => 'doc' }.freeze

  def up
    create_table :secretary_resource_types do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string :description, null: false
    end

    create_table :secretary_resources do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :secretary_resource_type, null: false, foreign_key: true
      t.string :key, null: false
      t.string :idioma
      t.text :resource_url
      t.text :caption
      t.timestamps
    end
    add_index :secretary_resources, [:account_id, :key, :idioma]

    TYPES.each { |id, description| execute "INSERT INTO secretary_resource_types (id, description) VALUES (#{id}, '#{description}')" }
  end

  def down
    drop_table :secretary_resources
    drop_table :secretary_resource_types
  end
end
