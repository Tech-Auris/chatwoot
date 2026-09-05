# Assinatura autenticada de um `TermsAcceptance` do dashboard.
#
# Endpoint aberto no dashboard só para gerentes que têm uma pendência de
# assinatura em uma campanha `update`. O aceite carrega, além do que o modelo
# já grava (signer, ip, ua, signed_at), um `OperationsNotificationAck` como
# efeito colateral — assim o mesmo modal que abre o gate no login some assim
# que o gerente confirma.
class Api::V1::Accounts::TermsAcceptancesController < Api::V1::Accounts::BaseController
  before_action :fetch_acceptance
  before_action :ensure_signer_is_current_account_user

  def sign
    @acceptance.sign!(signer: signer_details, ip_address: request.remote_ip, user_agent: request.user_agent)
    register_ack

    render json: { success: true, signed_at: @acceptance.signed_at.to_i }
  end

  private

  def fetch_acceptance
    @acceptance = TermsAcceptance
                  .kind_update
                  .where(account_id: current_account.id)
                  .find_by!(request_token: params[:token])
  end

  # A campaign pins one specific manager per row; nobody else can sign for
  # them. Blocking here beats a silent 200 that would move the audit trail
  # under the wrong name.
  def ensure_signer_is_current_account_user
    account_user = AccountUser.find_by(user_id: current_user.id, account_id: current_account.id)
    return if account_user && @acceptance.account_user_id == account_user.id

    render json: { error: 'Este aceite pertence a outro gerente' }, status: :forbidden
  end

  def signer_details
    {
      name: current_user.name.presence || current_user.email,
      email: current_user.email,
      document: nil
    }
  end

  # Closing the modal happens as a consequence of the signature — pairing
  # the ack to the sign avoids a second round-trip from the frontend and
  # keeps the two records in step.
  def register_ack
    notification = OperationsNotification.find_by(subject: @acceptance.terms_acceptance_request)
    return if notification.blank?

    OperationsNotificationAck.find_or_create_by!(
      operations_notification_id: notification.id,
      user_id: current_user.id
    ) do |ack|
      ack.account_id = current_account.id
      ack.acknowledged_at = Time.current
      ack.ip = request.remote_ip
      ack.user_agent = request.user_agent
    end
  end
end
