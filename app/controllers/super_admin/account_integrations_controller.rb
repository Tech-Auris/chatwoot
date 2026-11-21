class SuperAdmin::AccountIntegrationsController < SuperAdmin::ApplicationController
  # Opens the account's integration with the ERP: its edit form, or a new one.
  def configure
    integration = AccountIntegration.find_by(account_id: params[:account_id], erp_source_id: params[:erp_source_id])
    return redirect_to([:edit, namespace, integration]) if integration

    redirect_to new_super_admin_account_integration_path(account_id: params[:account_id], erp_source_id: params[:erp_source_id])
  end

  def scoped_resource
    resource_class.includes(:account, :erp_source).order(:account_id, :erp_source_id)
  end

  private

  # An integration is created from its account (account page or ERP field),
  # which says the account and the ERP, so the list has no "New" button.
  def new_resource(attributes = {})
    attributes = { account_id: params[:account_id], erp_source_id: params[:erp_source_id] } if attributes.blank?
    resource_class.new(attributes)
  end

  def authorized_action?(resource, action)
    return false if action.to_s == 'new' && action_name == 'index'

    super
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
