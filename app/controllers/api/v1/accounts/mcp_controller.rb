# Turns the Auris MCP on or off for the account. Turning it on requires the
# administrator to accept the term: the data the assistant reads is sent to
# the AI provider the clinic picks.
class Api::V1::Accounts::McpController < Api::V1::Accounts::BaseController
  def update
    authorize Current.account, :update?

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
