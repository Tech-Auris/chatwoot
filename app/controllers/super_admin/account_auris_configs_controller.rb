class SuperAdmin::AccountAurisConfigsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account, :auris_config).order(:account_id, :auris_config_id)
  end

  private

  # Opened from the account page with `account_id` (and `auris_config_id`),
  # so the form starts on them.
  def new_resource(attributes = {})
    resource_class.new(attributes.presence || params.permit(:account_id, :auris_config_id).to_h)
  end

  def after_resource_created_path(value)
    [namespace, value.account]
  end

  def after_resource_updated_path(value)
    [namespace, value.account]
  end

  def after_resource_destroyed_path(value)
    [namespace, value.account]
  end
end
