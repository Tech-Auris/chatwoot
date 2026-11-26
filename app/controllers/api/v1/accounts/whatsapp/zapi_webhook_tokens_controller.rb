class Api::V1::Accounts::Whatsapp::ZapiWebhookTokensController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  def create
    Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: @inbox.channel).rotate_webhook_token!
    head :ok
  rescue Whatsapp::Providers::WhatsappZapiService::ProviderUnavailableError
    render json: { message: 'Z-API did not accept the new webhook URL' }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :rotate_zapi_webhook_token?
    raise ActiveRecord::RecordNotFound unless @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'zapi'
  end
end
