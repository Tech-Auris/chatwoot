class AutomationRulePolicy < ApplicationPolicy
  # Managers are operational owners of the account (inboxes, teams,
  # agents, integrations) and need to configure the automations that
  # drive routing, tagging and follow-ups. Both roles get full CRUD;
  # agents remain excluded.
  def index?
    admin_or_manager?
  end

  def create?
    admin_or_manager?
  end

  def show?
    admin_or_manager?
  end

  def update?
    admin_or_manager?
  end

  def clone?
    admin_or_manager?
  end

  def destroy?
    admin_or_manager?
  end

  private

  def admin_or_manager?
    @account_user.administrator? || @account_user.manager?
  end
end
