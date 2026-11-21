# Everyone sees the clinic pipelines and moves contacts through them, as on
# the Agendamento; creating, configuring, archiving and deleting a pipeline
# is for administrators and managers.
class PipelinePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  def board?
    index?
  end

  def stage_entries?
    index?
  end

  def create?
    @account_user.administrator? || @account_user.manager?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def archive?
    create?
  end

  def unarchive?
    create?
  end
end
