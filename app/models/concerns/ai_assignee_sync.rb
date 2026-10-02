# Keeps the AI status in step with the AI user ("IA | Auris", set in Super
# Admin → Settings → Secretary): assigning a conversation to it turns the AI
# on, taking it away turns the AI off — whatever made the change (sidebar,
# context menu, bulk action, automation, API).
module AiAssigneeSync
  extend ActiveSupport::Concern

  AI_USER_CONFIG = 'SECRETARY_AI_USER_ID'.freeze

  included do
    before_save :sync_ai_status_with_ai_assignee, if: :will_save_change_to_assignee_id?
    after_commit :apply_pending_legacy_ai_status
  end

  class_methods do
    def ai_user_id
      GlobalConfigService.load(AI_USER_CONFIG, nil).to_i.nonzero?
    end
  end

  private

  def sync_ai_status_with_ai_assignee
    ai_user_id = self.class.ai_user_id
    return if ai_user_id.nil?

    previous_assignee_id, new_assignee_id = assignee_id_change_to_be_saved
    if new_assignee_id == ai_user_id
      assign_ai_status(true)
    elsif previous_assignee_id == ai_user_id
      assign_ai_status(false)
    end
  end

  # Attribute mode: the column change rides along with the assignee one.
  # Legacy label mode: the `agente-off` label is only written once the
  # assignee change is committed (tags are not saved from a before_save).
  def assign_ai_status(enabled)
    if account.ai_status_uses_attribute?
      self.ai_enabled = enabled
    else
      @pending_legacy_ai_status = enabled
    end
  end

  def apply_pending_legacy_ai_status
    return if @pending_legacy_ai_status.nil?

    enabled = @pending_legacy_ai_status
    @pending_legacy_ai_status = nil
    set_ai_status!(enabled)
  end
end
