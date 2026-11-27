# Account setting reopen_hands_to_ai: when a patient writes into a resolved conversation of an
# inbox the Secretária answers, the conversation reopens assigned to the AI user, so the AI
# status turns on (AiAssigneeSync) and the Secretária answers the message. It keeps its team.
# Nothing changes while the AI must stay off for the conversation (Conversations::AiAutoOffService).
module ReopenAiHandoffHandler
  extend ActiveSupport::Concern

  included do
    # Included after ReopenTeamAssigneeHandler, whose drop it overrides, and before
    # AiAssigneeSync, so the AI status follows the owner this settles in the same save.
    before_save :hand_reopened_conversation_to_ai, if: -> { @reopen_ai_judged }
  end

  # Called by the patient's message right before the status save that reopens the
  # conversation; the decision is taken inside that save, under the row lock.
  def hand_reopen_to_ai
    return unless reopen_handoff_to_ai_allowed?

    ai_held = assignee_id == self.class.ai_user_id
    return if ai_held && ai_status_enabled?

    @reopen_ai_judged = { assignee_id: assignee_id, assignee_name: (assignee&.name unless ai_held) }
  end

  private

  def reopen_handoff_to_ai_allowed?
    resolved? && !group_type_group? && account.reopen_hands_to_ai? && ai_can_answer?
  end

  def ai_can_answer?
    self.class.ai_user_id.present? && account.account_secretary&.version_for(inbox).present? &&
      Conversations::AiAutoOffService.reason_for(self).nil?
  end

  # An agent can reassign or reopen the conversation after the message read it and before this
  # save: their action wins, so the AI takes it only while the row is still resolved and still
  # held by the owner read.
  def hand_reopened_conversation_to_ai
    judged = @reopen_ai_judged
    @reopen_ai_judged = nil
    owner_id, persisted_status = self.class.lock.where(id: id).pick(:assignee_id, :status)
    return unless persisted_status == 'resolved' && owner_id == judged[:assignee_id]

    # The AI takes the conversation instead of it going to Unassigned.
    @reopen_team_unassignment = nil
    ai_user_id = self.class.ai_user_id
    # Already the AI's (its status was turned off without reassigning it): only the status turns on.
    return assign_ai_status(true) if owner_id == ai_user_id

    self.assignee_id = ai_user_id
    @reopen_ai_handoff = judged
  end

  def reopen_ai_handoff?
    @reopen_ai_handoff.present?
  end

  # Runs with no user (a patient's message did it), which would make the generic assignee
  # line name nobody or the automation system; the reason is the point of it anyway.
  def create_reopen_ai_handoff_activity
    previous_name = @reopen_ai_handoff[:assignee_name]
    @reopen_ai_handoff = nil
    content = if previous_name.present?
                I18n.t('conversations.activity.assignee.handed_to_ai_on_reopen_from', assignee_name: previous_name, locale: account.locale)
              else
                I18n.t('conversations.activity.assignee.handed_to_ai_on_reopen', locale: account.locale)
              end
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content))
  end
end
