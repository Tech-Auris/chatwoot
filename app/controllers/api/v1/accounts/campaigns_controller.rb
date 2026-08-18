class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create, :import_audience]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def create
    @campaign = Current.account.campaigns.create!(campaign_params)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  # Turns an uploaded CSV into contacts before the campaign is created, so the
  # operator sees what the file produced — and can fix it — instead of finding
  # out only when the campaign fires.
  def import_audience
    result = Campaigns::AudienceCsvImportService.new(account: Current.account, file: params.require(:file)).perform

    render json: result
  rescue Campaigns::AudienceCsvImportService::InvalidFile => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, :cadence_seconds, :conversation_label,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {})
  end
end
