class Api::V1::Accounts::MentionsController < Api::V1::Accounts::BaseController
  def unseen
    mentions = Current.account.mentions.unseen
                      .where(user: Current.user)
                      .joins(:conversation)
                      .where(conversations: { inbox_id: Current.user.assigned_inboxes.select(:id) })
                      .includes(:conversation, :mentioned_by)

    render json: { payload: mentions.map { |mention| unseen_mention_payload(mention) } }
  end

  private

  def unseen_mention_payload(mention)
    {
      conversation_id: mention.conversation.display_id,
      mentioned_at: mention.mentioned_at.to_i,
      mentioned_by: mention.mentioned_by && { id: mention.mentioned_by.id, name: mention.mentioned_by.available_name }
    }
  end
end
