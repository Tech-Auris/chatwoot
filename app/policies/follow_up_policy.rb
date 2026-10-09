# FUP records are written by the n8n workflow (administrator token or agent
# bot) and read by anyone who can see the conversation.
class FollowUpPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    administrator? || user.is_a?(AgentBot)
  end

  def update?
    create?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
