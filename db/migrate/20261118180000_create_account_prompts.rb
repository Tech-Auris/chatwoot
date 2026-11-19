class CreateAccountPrompts < ActiveRecord::Migration[7.1]
  def change
    create_table :account_prompts do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :ai_prompt_system_message, null: false
      t.bigint :inbox_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :account_prompts, :inbox_ids, using: :gin
    add_index :account_prompts, :account_id, unique: true, where: "inbox_ids = '{}'", name: 'index_account_prompts_one_general_per_account'
  end
end
