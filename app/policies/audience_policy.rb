# Any account user builds and browses audiences; downloading one and sending a
# campaign to it follow the campaigns' rule (administrators and managers).
class AudiencePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end

  def preview?
    true
  end

  def contacts?
    true
  end

  def snapshot?
    true
  end

  def add_contacts?
    true
  end

  def remove_contacts?
    true
  end

  def import?
    true
  end

  def export?
    @account_user.administrator? || @account_user.manager?
  end

  def use_in_campaign?
    export?
  end
end
