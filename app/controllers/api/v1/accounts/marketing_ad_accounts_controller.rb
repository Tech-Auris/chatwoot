# The ad accounts grid of a Meta integration (Marketing → Pixel e Dados):
# which accounts feed Gasto / CPL / CPA / ROAS, and how their last sync went.
# Same audience as the integration itself — administrators and managers.
class Api::V1::Accounts::MarketingAdAccountsController < Api::V1::Accounts::BaseController
  before_action :fetch_integration
  before_action :fetch_ad_account, only: [:update, :destroy]

  def index
    @integration.import_legacy_ad_account!
    @ad_accounts = @integration.ad_accounts.order(:created_at)
  end

  # Asks Meta for the account before saving it, so a token without access to
  # it is reported now rather than as an empty report tomorrow.
  def create
    @ad_account = @integration.ad_accounts.new(account: Current.account, external_id: params.require(:external_id))
    return render_record_invalid unless @ad_account.valid?

    lookup = Marketing::MetaAdAccountLookup.new(integration: @integration, external_id: @ad_account.external_id).perform
    return render json: { error: lookup.error }, status: :unprocessable_entity unless lookup.ok

    @ad_account.update!(name: lookup.name, currency: lookup.currency)
    render :show
  end

  def update
    @ad_account.update!(params.permit(:enabled))
    render :show
  end

  def destroy
    @ad_account.destroy!
    head :ok
  end

  def sync
    Marketing::MetaAdAccountsSyncJob.perform_later(Current.account.id)
    head :accepted
  end

  private

  def fetch_integration
    @integration = Current.account.marketing_integrations.find(params[:marketing_integration_id])
    authorize @integration, :update?
  end

  def fetch_ad_account
    @ad_account = @integration.ad_accounts.find(params[:id])
  end

  def render_record_invalid
    render json: { error: @ad_account.errors.messages.values.flatten.first }, status: :unprocessable_entity
  end
end
