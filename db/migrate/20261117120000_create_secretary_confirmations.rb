# The Supabase `confirmacoes` table: the column names are kept because n8n's
# Code nodes read them by name, and blank templates stay "" (not NULL) as there.
class CreateSecretaryConfirmations < ActiveRecord::Migration[7.1]
  def change
    create_table :secretary_confirmations do |t|
      t.references :account, null: false, foreign_key: true
      t.string :versao_workflow, index: true
      t.text :calendar_id
      t.string :inbox_id
      t.integer :unidade_id
      t.text :message
      t.text :message_96h
      t.text :message_72h
      t.text :message_48h
      t.text :message_hj
      t.text :message_2h
      t.text :message_30m
      t.timestamps
    end
  end
end
