class SuperAdmin::AiModelsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:ai_provider).order('ai_providers.name', :name).references(:ai_provider)
  end
end
