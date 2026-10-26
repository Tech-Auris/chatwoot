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

    hand_to_team if team
    conversation.set_ai_status!(false)
    note_handoff
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

  def note_handoff
    content = if team
                I18n.t('conversations.activity.ai_schedule.handed_to_team', team_name: team.name)
              else
                I18n.t('conversations.activity.ai_schedule.ai_off')
              end
    Conversations::ActivityMessageJob.perform_later(
      conversation, { account_id: conversation.account_id, inbox_id: inbox.id, message_type: :activity, content: content }
    )
  end
end
