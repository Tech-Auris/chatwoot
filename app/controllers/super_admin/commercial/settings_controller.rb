# Commercial → Settings: where the proposal messages to leads go out from (an
# account and one of its inboxes — the main seller's WhatsApp) and when the
# last-day reminder is sent.
class SuperAdmin::Commercial::SettingsController < SuperAdmin::ApplicationController
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  def show
    respond_to do |format|
      format.html
      format.json { render json: current_settings }
    end
  end

  def update
    inbox = Account.find_by(id: params[:account_id])&.inboxes&.find_by(id: params[:inbox_id])
    error = settings_error(inbox)
    return render json: { error: error }, status: :unprocessable_entity if error

    save('COMMERCIAL_WHATSAPP_ACCOUNT_ID', inbox.account_id.to_s)
    save('COMMERCIAL_WHATSAPP_INBOX_ID', inbox.id.to_s)
    save('COMMERCIAL_RESERVATION_REMINDER_TIME', params[:reminder_time].to_s)
    render json: current_settings
  end

  def accounts
    render json: Account.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  def inboxes
    account = Account.find(params.require(:account_id))
    render json: account.inboxes.order(:name).map { |inbox| { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type } }
  end

  private

  def settings_error(inbox)
    return 'Escolha uma conta e uma caixa dessa conta' if inbox.nil?

    'Informe o horário no formato HH:MM' unless params[:reminder_time].to_s.match?(TIME_FORMAT)
  end

  def current_settings
    {
      account_id: Sales::LeadWhatsappMessenger.account_id,
      inbox_id: Sales::LeadWhatsappMessenger.inbox_id,
      reminder_time: GlobalConfigService.load('COMMERCIAL_RESERVATION_REMINDER_TIME', nil).presence || Sales::ReservationReminderJob::DEFAULT_TIME
    }
  end

  def save(name, value)
    config = InstallationConfig.where(name: name).first_or_initialize
    config.update!(value: value, locked: false)
    GlobalConfig.clear_cache
  end
end
