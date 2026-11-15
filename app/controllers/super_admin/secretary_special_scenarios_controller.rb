class SuperAdmin::SecretarySpecialScenariosController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).order(:account_id, :name)
  end
end
