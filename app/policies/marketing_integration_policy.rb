# Only administrators and managers can see / edit / connect marketing
# provider credentials — they carry access tokens and pixel/customer ids
# that agents have no business handling.
class MarketingIntegrationPolicy < ApplicationPolicy
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

  def pixel_events?
    admin_or_manager?
  end

  private

  def admin_or_manager?
    @account_user.administrator? || @account_user.manager?
  end
end
