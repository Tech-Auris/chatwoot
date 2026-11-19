class SuperAdmin::AccountPromptsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).order(:account_id).ordered
  end

  private

  # Opened from the account page with `account_id`, so the form lists only that
  # account's inboxes and starts with the next prompt name.
  def new_resource(attributes = {})
    account = Account.find_by(id: params[:account_id]) if attributes.blank?
    return resource_class.new(attributes) if account.nil?

    resource_class.new(account: account, name: resource_class.default_name_for(account))
  end

  def after_resource_created_path(prompt)
    [namespace, prompt.account]
  end

  def after_resource_updated_path(prompt)
    [namespace, prompt.account]
  end

  def after_resource_destroyed_path(prompt)
    [namespace, prompt.account]
  end
end
