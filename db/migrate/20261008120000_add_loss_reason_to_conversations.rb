# The loss reason lived only in the funnel history, so rules (automations,
# CSAT) could not ask "lost because of what?" with a plain column filter. The
# conversation now keeps the reason of the lost stage it is in; the backfill
# takes it from the latest move into that stage.
class AddLossReasonToConversations < ActiveRecord::Migration[7.1]
  def up
    add_reference :conversations, :loss_reason, foreign_key: { on_delete: :nullify }, index: true

    execute <<~SQL.squish
      UPDATE conversations
      SET loss_reason_id = latest.loss_reason_id
      FROM (
        SELECT DISTINCT ON (changes.conversation_id) changes.conversation_id, changes.loss_reason_id
        FROM funnel_stage_changes changes
        JOIN conversations c ON c.id = changes.conversation_id
        JOIN funnel_stages stages ON stages.id = c.funnel_stage_id AND stages.name = changes.new_stage
        WHERE stages.requires_loss_reason AND changes.loss_reason_id IS NOT NULL
        ORDER BY changes.conversation_id, changes.created_at DESC
      ) latest
      WHERE conversations.id = latest.conversation_id
    SQL
  end

  def down
    remove_reference :conversations, :loss_reason, foreign_key: true, index: true
  end
end
