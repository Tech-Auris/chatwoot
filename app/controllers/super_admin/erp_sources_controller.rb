class SuperAdmin::ErpSourcesController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.ordered
  end

  private

  # Administrate reads any nested param with a `type` as a polymorphic
  # reference; the integration field rows have one, so they skip that step.
  def resource_params
    params.require(resource_class.model_name.param_key).permit(dashboard.permitted_attributes(action_name))
  end
end
