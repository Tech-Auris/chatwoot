# Turns the Auris MCP on or off for the account (administrators and
# managers). Turning it on requires accepting the term on behalf of the
# clinic: the data the assistant reads is sent to the AI provider it picks.
class Api::V1::Accounts::McpController < Api::V1::Accounts::BaseController
  def update
    authorize Current.account, :update_mcp?

    if ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
      return render json: { error: I18n.t('errors.mcp.terms_required') }, status: :unprocessable_entity unless terms_accepted?

      Current.account.enable_mcp!(Current.user)
    else
      Current.account.disable_mcp!
    end

    @account = Current.account
    render 'api/v1/accounts/show', format: :json
  end

  private

  def terms_accepted?
    ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
  end
end
