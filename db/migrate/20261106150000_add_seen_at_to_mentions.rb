class AddSeenAtToMentions < ActiveRecord::Migration[7.1]
  def up
    add_column :mentions, :seen_at, :datetime
    add_column :mentions, :mentioned_by_id, :bigint
    # Existing mentions predate the unseen indicator; treat them as seen so
    # nobody gets a backlog badge on deploy.
    execute 'UPDATE mentions SET seen_at = mentioned_at'
    add_index :mentions, [:user_id, :account_id], where: 'seen_at IS NULL', name: 'index_mentions_unseen_on_user_and_account'
  end

  def down
    remove_index :mentions, name: 'index_mentions_unseen_on_user_and_account'
    remove_column :mentions, :mentioned_by_id
    remove_column :mentions, :seen_at
  end
end
