class ContactPolicy < ApplicationPolicy
  def index?
    true
  end

  def active?
    true
  end

  # Managers run the contact base day to day — they already create, edit and
  # delete contacts here — so moving the list in and out is theirs as well.
  def import?
    @account_user.administrator? || @account_user.manager?
  end

  def export?
    @account_user.administrator? || @account_user.manager?
  end

  # Same data, same gate — downloading the file must not be reachable by
  # someone who cannot ask for it by e-mail.
  def export_download?
    export?
  end

  def search?
    true
  end

  def filter?
    true
  end

  def update?
    true
  end

  def contactable_inboxes?
    true
  end

  def destroy_custom_attributes?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def avatar?
    true
  end

  def sync_group?
    true
  end

  def destroy?
    @account_user.administrator? || @account_user.manager?
  end
end
