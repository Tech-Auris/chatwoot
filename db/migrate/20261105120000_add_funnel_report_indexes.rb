class AddFunnelReportIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Funnel → Conversão looks up campaign sends among an account's outgoing
    # messages. Indexing only campaign messages keeps that lookup off the rest
    # of the table (it scanned every outgoing message on large accounts).
    add_index :messages, [:account_id, :created_at],
              name: 'index_messages_on_account_created_campaign',
              where: "message_type = 1 AND (additional_attributes ->> 'campaign_id') IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true

    # Funnel → Visão geral counts an account's conversations per current stage.
    add_index :conversations, [:account_id, :funnel_stage_id],
              name: 'index_conversations_on_account_id_and_funnel_stage_id',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
