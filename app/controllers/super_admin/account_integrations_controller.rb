class SuperAdmin::AccountIntegrationsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account, :erp_source).order(:account_id, :erp_source_id)
  end

  private

  # Opened from the account page with `account_id`, so the form starts on the
  # account's ERP with that ERP's keys.
  def new_resource(attributes = {})
    account = Account.find_by(id: params[:account_id]) if attributes.blank?
    return resource_class.new(attributes) if account.nil?

    resource_class.new(account: account, erp_source_id: account.erp_source_id, config: resource_class.template_for(account.erp_source_id))
  end

  def after_resource_created_path(integration)
    [namespace, integration.account]
  end

  def after_resource_updated_path(integration)
    [namespace, integration.account]
  end

  def after_resource_destroyed_path(integration)
    [namespace, integration.account]
  end
end
