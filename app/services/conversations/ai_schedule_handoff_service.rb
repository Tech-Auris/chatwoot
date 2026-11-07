# A patient message in the inbox's "Horário da IA desligada" hands the
# conversation to the inbox's team and turns the AI off, before the message
# reaches the webhooks: the AI secretary still gets it, with `ai_enabled:
# false`, and keeps it as context without replying. Nothing changes when the
# AI is already off; when the schedule ends, the team returns the
# conversation to the AI by assigning it.
class Conversations::AiScheduleHandoffService
  pattr_initialize [:message!]

  def perform
    return unless applies?

    # Handing to the team can already turn the AI off (the AI user leaves the
    # assignee), so the flag covers the whole handoff.
    Current.ai_off_by_schedule = true
    hand_to_team if team
    conversation.set_ai_status!(false)
  ensure
    Current.ai_off_by_schedule = nil
  end

  private

  delegate :conversation, :inbox, to: :message

  def applies?
    message.incoming? && !message.private? && !conversation.group_type_group? &&
      inbox.ai_off_now? && conversation.ai_status_enabled?
  end

  def team
    @team ||= inbox.ai_schedule_team
  end

  def hand_to_team
    if conversation.team_id != team.id
      conversation.update!(team: team)
    elsif team.allow_auto_assign && !team.members.exists?(id: conversation.assignee_id)
      conversation.reassign_within_team!
    end
    AiAssignmentAttempt.record_for(conversation, triggered_by: ai_user, reason: :schedule)
  end

  def ai_user
    User.find_by(id: Conversation.ai_user_id)
  end
end
