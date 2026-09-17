class AddOrigemToConversations < ActiveRecord::Migration[7.1]
  # Origem do lead moves from Contact (single value, first-touch) to Conversation
  # so the sidebar / filters / automation / report can distinguish where each
  # engagement really came from. Column instead of additional_attributes because
  # the filter + report do `WHERE origem = ?` a lot.
  def change
    add_column :conversations, :origem, :string
    add_index :conversations, %i[account_id origem]
  end
end
