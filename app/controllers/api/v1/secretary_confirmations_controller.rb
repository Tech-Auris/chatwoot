# Read by the n8n `7. Confirmacoes` flows (V2, V3, V5.1): the reminder rows of
# the asked `versao_workflow`s, from every account the caller administers.
# Same shape as the Supabase `SELECT cf.*, c.id AS cliente_id` it replaces.
# Managed in Super Admin.
class Api::V1::SecretaryConfirmationsController < Api::BaseController
  def index
    administered = current_user.account_users.administrator.select(:account_id)
    @secretary_confirmations = SecretaryConfirmation.where(account_id: administered)
                                                    .for_versions(params.require(:versao_workflow).split(','))
                                                    .order(:account_id, :id)
    @secretary_confirmations = @secretary_confirmations.where(account_id: params[:account_id]) if params[:account_id].present?
    @secretary_confirmations = @secretary_confirmations.where.not(account_id: params[:except_account_id]) if params[:except_account_id].present?
  end
end
