# The pixels of a Meta integration (Marketing → Pixel e Dados): every pixel in
# `test_mode` or `active` gets the account's conversions, each sent with its
# own access token. Same audience as the integration — administrators and
# managers. The token is write-only: a blank one on update keeps the stored.
class Api::V1::Accounts::MarketingPixelsController < Api::V1::Accounts::BaseController
  before_action :fetch_integration
  before_action :fetch_pixel, only: [:update, :destroy]

  def index
    @pixels = @integration.pixels
  end

  def create
    @pixel = @integration.pixels.create!(pixel_params.merge(account: Current.account))
    render :show
  end

  def update
    attributes = pixel_params
    attributes = attributes.except(:access_token) if attributes[:access_token].blank?
    @pixel.update!(attributes)
    render :show
  end

  def destroy
    @pixel.destroy!
    head :ok
  end

  private

  # The form shows the message as is, without the attribute name in front.
  def render_record_invalid(exception)
    render json: { message: exception.record.errors.messages.values.flatten.first }, status: :unprocessable_entity
  end

  def fetch_integration
    @integration = Current.account.marketing_integrations.meta_capi.find(params[:marketing_integration_id])
    authorize @integration, :update?
  end

  def fetch_pixel
    @pixel = @integration.pixels.find(params[:id])
  end

  def pixel_params
    params.permit(:name, :pixel_id, :access_token, :test_event_code, :status)
  end
end
