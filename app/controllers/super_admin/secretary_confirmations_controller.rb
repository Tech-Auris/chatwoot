class SuperAdmin::SecretaryConfirmationsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).order(:account_id, :id)
  end
end
