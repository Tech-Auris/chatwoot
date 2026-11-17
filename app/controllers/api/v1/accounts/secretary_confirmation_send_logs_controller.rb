# The n8n confirmation flows' dedupe log (the Supabase `confirmacoes_send_log`).
# `index` replaces their `SelectExistentes`; `create` replaces `CreateLogRow`
# and is atomic, so a flow that logs before sending can trust `send`.
class Api::V1::Accounts::SecretaryConfirmationSendLogsController < Api::V1::Accounts::BaseController
  def index
    @send_logs = Current.account.secretary_confirmation_send_logs.where(event_id: params.require(:event_ids).split(',')).order(:id)
  end

  def create
    reserved = SecretaryConfirmationSendLog.reserve(account: Current.account, event_id: params.require(:event_id),
                                                    reminder_type: params.require(:reminder_type), calendar_id: params[:calendar_id])
    render json: { send: reserved }, status: reserved ? :created : :ok
  end
end
