class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  PREVIEW_PER_PAGE = 25
  REPORT_PER_PAGE = 25

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

  # Delivery report of a campaign: the totals on top and one row per message,
  # so the team can tell what actually reached each contact.
  def report
    messages = campaign_messages
    page = messages.reorder(created_at: :desc).page(params[:page] || 1).per(REPORT_PER_PAGE)

    render json: {
      campaign: serialized_campaign,
      summary: report_summary(messages),
      messages: page.map { |message| serialize_report_message(message) },
      meta: {
        current_page: page.current_page,
        total_pages: page.total_pages,
        total_count: page.total_count
      }
    }
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

  # Rendered through the same partial the list screen uses, so the report page
  # can show the campaign with the very same card instead of a second, drifting
  # copy of those fields.
  def serialized_campaign
    JSON.parse(
      render_to_string(partial: 'api/v1/models/campaign', formats: [:json], locals: { resource: @campaign })
    )
  end

  # Messages carry the campaign id inside `additional_attributes`. The window
  # on `created_at` keeps the lookup off a full scan of a very large table —
  # nothing from this campaign can predate its own schedule.
  def campaign_messages
    Current.account.messages
           .where('messages.created_at >= ?', (@campaign.scheduled_at || @campaign.created_at) - 1.hour)
           .where("messages.additional_attributes ->> 'campaign_id' = ?", @campaign.id.to_s)
  end

  def report_summary(messages)
    counts = messages.reorder(nil).group(:status).count
    total = counts.values.sum
    failed = counts['failed'].to_i
    delivered = counts['delivered'].to_i + counts['read'].to_i

    {
      total: total,
      accepted: total - failed,
      failed: failed,
      delivered: delivered,
      read: counts['read'].to_i,
      # Accepted by Meta over everything we tried to send. Delivery to the
      # handset is reported separately, since it depends on the recipient.
      success_rate: total.zero? ? 0 : ((total - failed).to_f / total * 100).round(1)
    }
  end

  def serialize_report_message(message)
    contact = message.conversation&.contact

    {
      id: message.id,
      status: message.status,
      # Campaign messages are created together and dispatched apart, so the
      # send time is the stamped dispatch — creation only answers for messages
      # that predate the pacing.
      sent_at: message.additional_attributes&.dig('campaign_dispatch_at') || message.created_at.to_i,
      created_at: message.created_at.to_i,
      error: message.external_error,
      contact_name: contact&.name,
      contact_phone: contact&.phone_number,
      conversation_id: message.conversation&.display_id
    }
  end

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
