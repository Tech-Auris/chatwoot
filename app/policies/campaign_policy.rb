class CampaignPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager?
  end

  def update?
    @account_user.administrator? || @account_user.manager?
  end

  def show?
    @account_user.administrator? || @account_user.manager?
  end

  def create?
    @account_user.administrator? || @account_user.manager?
  end

  def destroy?
    @account_user.administrator? || @account_user.manager?
  end

  # Turning a CSV into the audience is part of creating a campaign, so it
  # follows the same rule. Without this the shared `check_authorization`
  # looks for a policy method that doesn't exist and the request 500s.
  def import_audience?
    create?
  end

  def audience_preview?
    create?
  end
end
