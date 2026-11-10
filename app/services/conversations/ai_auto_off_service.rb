# Turns the AI off on a patient message before it reaches the webhooks: the AI
# secretary still gets it, with `ai_enabled: false`, and keeps it as context
# without replying. The first rule that applies decides:
#   1. contact  — the contact has the AI off ("IA responde este contato");
#   2. inbox    — the inbox has the AI paused ("IA ativa nesta caixa");
#   3. schedule — the inbox's "Horário da IA desligada", which also hands the
#                 conversation to the inbox's team.
# Nothing changes when the AI is already off.
class Conversations::AiAutoOffService
  pattr_initialize [:message!]

  def perform
    return unless applies?

    # Handing to the team can already turn the AI off (the AI user leaves the
    # assignee), so the reason covers the whole handoff.
    Current.ai_off_reason = reason
    hand_to_team if reason == :schedule && team
    conversation.set_ai_status!(false)
  ensure
    Current.ai_off_reason = nil
  end

  private

  delegate :conversation, :inbox, to: :message

  def applies?
    message.incoming? && !message.private? && !conversation.group_type_group? &&
      conversation.ai_status_enabled? && reason.present?
  end

  def reason
    @reason ||= if conversation.contact&.ai_disabled? then :contact
                elsif inbox.ai_paused? then :inbox
                elsif inbox.ai_off_now? then :schedule
                end
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
