class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]

  def index
    render json: canned_responses
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)
    @canned_response.save!
    render json: @canned_response
  end

  def update
    @canned_response.update!(canned_response_params)
    render json: @canned_response
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, :inbox_id)
  end

  # With an inbox given — the composer asking what to offer inside a
  # conversation — the list narrows to the global responses plus that inbox's.
  # Without it, as on the settings screen, everything is listed.
  def canned_responses
    scope = Current.account.canned_responses.available_for_inbox(params[:inbox_id])
    return scope if params[:search].blank?

    scope.where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
         .order_by_search(params[:search])
  end
end
