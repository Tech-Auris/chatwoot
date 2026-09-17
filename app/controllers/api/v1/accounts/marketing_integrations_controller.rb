class Api::V1::Accounts::MarketingIntegrationsController < Api::V1::Accounts::BaseController
  before_action :fetch_integration, except: [:index, :create]
  before_action :check_authorization

  def index
    @integrations = policy_scope(Current.account.marketing_integrations)
  end

  def show; end

  def create
    @integration = Current.account.marketing_integrations.build(permitted_params)
    apply_credentials(@integration)
    @integration.save!
    render :show
  end

  def update
    @integration.assign_attributes(permitted_params.except(:credentials))
    apply_credentials(@integration)
    @integration.save!
    render :show
  end

  def destroy
    @integration.destroy!
    head :ok
  end

  private

  def fetch_integration
    @integration = Current.account.marketing_integrations.find(params[:id])
  end

  # `credentials` arrives as a nested hash on the form; the model serializes
  # it to `credentials_ciphertext` and encrypts at rest.
  def apply_credentials(integration)
    return unless params[:credentials].is_a?(ActionController::Parameters) || params[:credentials].is_a?(Hash)

    integration.credentials = integration.credentials.merge(permitted_credentials)
  end

  def permitted_credentials
    keys = if @integration&.persisted?
             persisted_provider_keys
           else
             params[:provider].to_s == 'meta_capi' ? MarketingIntegration::META_CAPI_KEYS : MarketingIntegration::GOOGLE_ADS_KEYS
           end
    params.require(:credentials).permit(*keys).to_h
  end

  def persisted_provider_keys
    @integration.meta_capi? ? MarketingIntegration::META_CAPI_KEYS : MarketingIntegration::GOOGLE_ADS_KEYS
  end

  def permitted_params
    params.permit(:provider, :status)
  end
end
