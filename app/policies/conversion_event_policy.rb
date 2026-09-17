# Same gate as marketing integrations — conversion mapping is admin/manager
# scope (agents fire the triggers by moving stages / adding labels).
class ConversionEventPolicy < ApplicationPolicy
  def index?
    admin_or_manager?
  end

  def show?
    admin_or_manager?
  end

  def create?
    admin_or_manager?
  end

  def update?
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
