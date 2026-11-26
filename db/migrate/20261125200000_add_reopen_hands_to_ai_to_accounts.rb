class AddReopenHandsToAiToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :reopen_hands_to_ai, :boolean, default: false, null: false
  end
end
