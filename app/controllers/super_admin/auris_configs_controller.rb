class SuperAdmin::AurisConfigsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.order(:id)
  end
end
