# Whether the AI (n8n) breaks its reply into one WhatsApp message per line
# break. Nullable on purpose: `nil` means "follow the channel default"
# (split everywhere except official WhatsApp Cloud, which Meta bills per
# message from 2026-10-01), so no backfill is needed and an inbox that later
# converts to Cloud picks up the right default on its own.
class AddSplitMessagesToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :split_messages, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn
  end
end
