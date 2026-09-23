class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  def move?
    index?
  end

  def history?
    index?
  end

  def conversation_status?
    index?
  end

  def stage_conversations?
    index?
  end
end
