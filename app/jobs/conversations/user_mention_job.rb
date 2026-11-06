class Conversations::UserMentionJob < ApplicationJob
  queue_as :default

  def perform(mentioned_user_ids, conversation_id, account_id, mentioned_by_id = nil)
    mentioned_user_ids.each do |mentioned_user_id|
      mention = Mention.find_or_initialize_by(
        user_id: mentioned_user_id,
        conversation_id: conversation_id,
        account_id: account_id
      )
      now = Time.zone.now
      self_mention = mentioned_by_id.present? && mentioned_user_id.to_i == mentioned_by_id.to_i

      mention.update!(
        mentioned_at: now,
        mentioned_by_id: mentioned_by_id,
        seen_at: self_mention ? now : nil
      )
    end
  end
end
