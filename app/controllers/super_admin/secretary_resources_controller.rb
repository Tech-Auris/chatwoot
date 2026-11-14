class SuperAdmin::SecretaryResourcesController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account, :secretary_resource_type).order(:account_id, :key, :idioma)
  end
end
