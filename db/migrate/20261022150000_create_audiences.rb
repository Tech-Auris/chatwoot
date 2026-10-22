class CreateAudiences < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :audiences do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.string :source, null: false, default: 'manual'
      t.jsonb :rule, null: false, default: []
      t.jsonb :exclusion, null: false, default: []
      t.jsonb :window, null: false, default: { type: 'all' }
      t.integer :contacts_count, null: false, default: 0
      t.datetime :counted_at
      t.references :created_by, index: false
      t.timestamps
    end

    create_table :audience_contacts do |t|
      t.references :audience, null: false, index: false
      t.references :contact, null: false, index: true
      t.timestamps
    end
    add_index :audience_contacts, [:audience_id, :contact_id], unique: true

    create_table :audience_events do |t|
      t.references :audience, null: false, index: true
      t.integer :kind, null: false
      t.references :user, index: false
      t.references :campaign, index: false
      t.integer :contacts_count, null: false, default: 0
      t.string :format
      t.timestamps
    end
  end
end
