class CreateInboxPrompts < ActiveRecord::Migration[7.1]
  def change
    create_table :inbox_prompts do |t|
      t.references :account, null: false, foreign_key: true
      t.text :ai_prompt_system_message, null: false
      t.bigint :inbox_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :inbox_prompts, :inbox_ids, using: :gin
  end
end
