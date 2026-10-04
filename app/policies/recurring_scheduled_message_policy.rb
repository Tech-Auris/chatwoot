class RecurringScheduledMessagePolicy < ApplicationPolicy
  def index?
    accessible?
  end

  def create?
    accessible?
  end

  # An agent changes or cancels only what they scheduled; administrators,
  # managers and bots can touch anyone's.
  def update?
    accessible? && (supervisor? || author?)
  end

  def destroy?
    accessible? && (supervisor? || author?)
  end

  private

  def supervisor?
    administrator? || account_user&.manager? || agent_bot?
  end

  def author?
    record.respond_to?(:author) && record.author == user
  end

  # Managers see every inbox of the account, like administrators.
  def accessible?
    supervisor? || agent_can_view_conversation?
  end

  def agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def conversation
    record.respond_to?(:conversation) ? record.conversation : record
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: conversation.inbox_id)
  end

  def team_access?
    return false if conversation.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: conversation.team_id)
  end
end

RecurringScheduledMessagePolicy.prepend_mod_with('RecurringScheduledMessagePolicy')
