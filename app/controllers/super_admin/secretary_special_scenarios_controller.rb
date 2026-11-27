class SuperAdmin::SecretarySpecialScenariosController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).order(:account_id, :name)
  end

  private

  # Opened from the account page with `account_id`, so the form starts on that account.
  def new_resource(attributes = {})
    return resource_class.new(attributes) if attributes.present?

    resource_class.new(account: Account.find_by(id: params[:account_id]))
  end

  def after_resource_created_path(scenario)
    [namespace, scenario.account]
  end

  def after_resource_updated_path(scenario)
    [namespace, scenario.account]
  end

  def after_resource_destroyed_path(scenario)
    [namespace, scenario.account]
  end
end
