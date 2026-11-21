# Adding, moving and removing contacts of a clinic pipeline is open to every
# role, the same as moving a card on the Agendamento.
class PipelineEntryPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def create?
    index?
  end

  def move?
    index?
  end

  def destroy?
    index?
  end

  def events?
    index?
  end
end
