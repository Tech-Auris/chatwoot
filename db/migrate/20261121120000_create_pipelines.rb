# Clinic pipelines (funis da clínica). Unlike the Agendamento funnel
# (`funnel_stages`, global and per conversation), a pipeline belongs to one
# account, follows the contact and lets the same contact sit in many
# pipelines at once. Every pass of a contact through a pipeline is an entry;
# only one entry per pipeline and contact can be open (closed_at IS NULL),
# Ganho / Perdido close it and the contact may come back later.
class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_pipelines
    create_pipeline_stages
    create_pipeline_entries
    create_pipeline_entry_events
  end

  private

  def create_pipelines
    create_table :pipelines do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end
    add_index :pipelines, %i[account_id name], unique: true
  end

  def create_pipeline_stages
    create_table :pipeline_stages do |t|
      t.references :pipeline, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :kind, null: false, default: 0
      t.string :color, null: false
      t.timestamps
    end
    add_index :pipeline_stages, %i[pipeline_id name], unique: true
  end

  def create_pipeline_entries
    create_table :pipeline_entries do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :pipeline, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :pipeline_stage, null: false, foreign_key: true, index: false
      t.datetime :stage_entered_at, null: false
      t.datetime :closed_at
      t.integer :source, null: false, default: 0
      t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
      # What put the contact in the pipeline (an automation rule, a campaign),
      # kept for the post-sales report to come.
      t.references :origin, polymorphic: true
      t.references :loss_reason, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :pipeline_entries, %i[pipeline_id contact_id], unique: true, where: 'closed_at IS NULL',
                                                             name: 'index_pipeline_entries_one_open_per_contact'
    add_index :pipeline_entries, %i[account_id pipeline_stage_id]
    add_index :pipeline_entries, %i[pipeline_id pipeline_stage_id stage_entered_at], name: 'index_pipeline_entries_on_board'
  end

  def create_pipeline_entry_events
    create_table :pipeline_entry_events do |t|
      t.references :pipeline_entry, null: false, foreign_key: { on_delete: :cascade }
      t.references :pipeline, null: false, foreign_key: { on_delete: :cascade }
      t.references :from_stage, foreign_key: { to_table: :pipeline_stages, on_delete: :nullify }
      t.references :to_stage, foreign_key: { to_table: :pipeline_stages, on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :source, null: false
      t.text :reason
      t.references :loss_reason, foreign_key: { on_delete: :nullify }
      t.datetime :created_at, null: false
    end
  end
end
