class SuperAdmin::InboxPromptsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).order(:account_id, :id)
  end

  private

  # Opened from the account page with `account_id`, so the form lists only that
  # account's inboxes.
  def new_resource(attributes = {})
    resource_class.new(attributes.presence || { account_id: params[:account_id] })
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
