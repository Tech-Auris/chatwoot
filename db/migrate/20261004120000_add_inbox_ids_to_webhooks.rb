# A webhook can now listen to several inboxes. An empty list keeps meaning
# "every inbox, including the ones created later". `inbox_id` stays in place
# untouched so a rollback to the previous release still finds it.
class AddInboxIdsToWebhooks < ActiveRecord::Migration[7.1]
  def up
    add_column :webhooks, :inbox_ids, :integer, array: true, default: [], null: false
    execute 'UPDATE webhooks SET inbox_ids = ARRAY[inbox_id] WHERE inbox_id IS NOT NULL'
  end

  def down
    remove_column :webhooks, :inbox_ids
  end
end
