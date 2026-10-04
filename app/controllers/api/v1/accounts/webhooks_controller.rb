class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_create_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_update_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  private

  def webhook_create_params
    webhook_params
  end

  def webhook_update_params
    webhook_params
  end

  # `inbox_id` (a single inbox) is still accepted for API clients written
  # before webhooks could listen to several inboxes.
  def webhook_params
    permitted = params.require(:webhook).permit(:inbox_id, :name, :url, subscriptions: [], inbox_ids: [])
    legacy_inbox_id = permitted.delete(:inbox_id)
    permitted[:inbox_ids] = Array(legacy_inbox_id.presence) if params[:webhook].key?(:inbox_id) && !permitted.key?(:inbox_ids)
    permitted
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
