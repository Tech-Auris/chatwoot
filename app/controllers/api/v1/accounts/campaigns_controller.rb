class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  PREVIEW_PER_PAGE = 25

  before_action :campaign, except: [:index, :create, :import_audience, :audience_preview]
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

  # Lists exactly who the campaign would reach, for either audience source, so
  # the operator can check the list before scheduling instead of after.
  def audience_preview
    contacts = preview_contacts.page(params[:page] || 1).per(PREVIEW_PER_PAGE)

    render json: {
      contacts: contacts.map { |contact| serialize_preview_contact(contact) },
      meta: {
        current_page: contacts.current_page,
        total_pages: contacts.total_pages,
        total_count: contacts.total_count,
        without_phone_count: preview_contacts.where(phone_number: [nil, '']).count
      }
    }
  end

  private

  # Mirrors Whatsapp::OneoffCampaignService: an explicit contact list wins,
  # otherwise the labels select the audience.
  def preview_contacts
    @preview_contacts ||= begin
      contact_ids = Array(params[:contact_ids]).compact_blank
      if contact_ids.any?
        Current.account.contacts.where(id: contact_ids).order(:name)
      else
        labels = Current.account.labels.where(id: Array(params[:label_ids]).compact_blank).pluck(:title)
        Current.account.contacts.tagged_with(labels, any: true).order(:name)
      end
    end
  end

  def serialize_preview_contact(contact)
    {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      # The campaign skips contacts without a number, so the preview says so
      # up front rather than letting them silently drop at send time.
      will_receive: contact.phone_number.present?
    }
  end

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, :cadence_seconds, :conversation_label, :audience_file_name,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {})
  end
end
