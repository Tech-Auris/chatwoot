class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!
    process_audience
  end

  # One contact's conversation, label and template message, run by
  # Campaigns::DispatchContactJob at its slot in the campaign.
  def dispatch_contact(contact)
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"
    return unless eligible_contact?(contact)

    rendered_template_params = render_template_params_for(contact)
    rendered_body = render_template_body(rendered_template_params)
    return log_skip(contact, 'template body could not be rendered') if rendered_body.blank?

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return log_skip(contact, 'failed to resolve contact inbox') if contact_inbox.blank?

    dispatch_to(contact_inbox, rendered_body, rendered_template_params)
  rescue StandardError => e
    Rails.logger.error "Failed to dispatch campaign message to #{contact.name}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    nil
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' if channel.provider != 'whatsapp_cloud'
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = audience_ids_for('Label')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def audience_ids_for(type)
    campaign.audience.select { |audience| audience['type'] == type }.pluck('id')
  end

  # The audience is either a set of contact labels or an explicit list of
  # contacts, the latter coming from the CSV the operator uploaded when
  # creating the campaign.
  def record_opted_out_count
    opted_out = audience_contacts.where(marketing_opt_out: true).where.not(phone_number: [nil, ''])
    campaign.update_column(:skipped_opt_out_count, opted_out.count) # rubocop:disable Rails/SkipsModelValidations
  end

  def recipient_ids
    audience_contacts.where(marketing_opt_out: false).where.not(id: already_reached_contact_ids).pluck(:id)
  end

  def saved_audience?
    audience_ids_for('Audience').any?
  end

  # A saved audience is read once, when the campaign starts: its contacts
  # right now become the campaign's own list, so pausing and resuming never
  # changes who receives it, and whoever enters the audience later is not
  # reached. Nothing goes out when the audience is gone, empty or over the
  # limit.
  def freeze_saved_audience
    source = campaign.account.audiences.find_by(id: audience_ids_for('Audience').first)
    contact_ids = source ? source.contacts.pluck(:id) : []
    if contact_ids.empty? || contact_ids.size > Audience::MAX_CONTACTS
      Rails.logger.warn "Campaign #{campaign.id}: saved audience #{source&.id} has #{contact_ids.size} contacts, nothing sent"
      return false
    end

    campaign.update_columns(audience: contact_ids.map { |id| { 'type' => 'Contact', 'id' => id } }, # rubocop:disable Rails/SkipsModelValidations
                            audience_source_id: source.id)
    source.events.create!(kind: :campaign, campaign: campaign, contacts_count: contact_ids.size)
  end

  # Contacts that already got this campaign's message never get it twice.
  def already_reached_contact_ids
    Conversation.where(account_id: campaign.account_id)
                .joins(:messages)
                .where("messages.additional_attributes ->> 'campaign_id' = ?", campaign.id.to_s)
                .select(:contact_id)
  end

  def audience_contacts
    contact_ids = audience_ids_for('Contact')
    return campaign.account.contacts.where(id: contact_ids) if contact_ids.any?

    campaign.account.contacts.tagged_with(extract_audience_labels, any: true)
  end

  def dispatch_to(contact_inbox, rendered_body, rendered_template_params)
    conversation = build_campaign_conversation(contact_inbox)
    apply_conversation_label(conversation)
    build_outgoing_template_message(conversation, rendered_body, rendered_template_params)
  end

  def eligible_contact?(contact)
    return log_skip(contact, 'no phone number') && false if contact.phone_number.blank?
    return log_skip(contact, 'no template_params found for WhatsApp campaign') && false if campaign.template_params.blank?
    return skip_opted_out(contact) if contact.marketing_opt_out?

    true
  end

  # Opted out after the campaign was scheduled, before its turn came.
  def skip_opted_out(contact)
    Campaign.update_counters(campaign.id, skipped_opt_out_count: 1) # rubocop:disable Rails/SkipsModelValidations
    log_skip(contact, 'marketing opt-out')
    false
  end

  def log_skip(contact, reason)
    Rails.logger.info "Skipping contact #{contact.name} - #{reason}"
    nil
  end

  # One job per contact, a cadence apart: the first right away, each next one
  # an interval later. Each job then sends its message half an interval after
  # creating it (Campaigns::PacedDispatchService), so creating and sending
  # alternate instead of piling up.
  # Contacts with the marketing opt-out on are left out, and counted for the
  # campaign report ("Não enviados (opt-out)").
  def process_audience
    return if saved_audience? && !freeze_saved_audience

    record_opted_out_count
    contact_ids = recipient_ids
    Rails.logger.info "Scheduling #{contact_ids.size} contacts for campaign #{campaign.id}"

    cadence = campaign.cadence_seconds.to_i
    contact_ids.each_with_index do |contact_id, index|
      Campaigns::DispatchContactJob.set(wait: index * cadence).perform_later(campaign.id, contact_id)
    end
  end

  def render_template_params_for(contact)
    Whatsapp::CampaignTemplateLiquidRenderer.new(
      campaign: campaign,
      contact: contact,
      template_params: campaign.template_params
    ).call
  end

  def render_template_body(template_params)
    Whatsapp::TemplateBodyRenderer.new(
      channel: channel,
      template_params: template_params
    ).call
  end

  # Status policy when the contact already has a conversation in this inbox:
  #   open      -> reuse, stays open (message joins the live thread)
  #   pending   -> reuse, stays pending (campaign is colder traffic, no agent change)
  #   snoozed   -> reuse, stays snoozed (agent snoozed on purpose; respect it)
  #   resolved  -> follows the inbox's "Roteamento de Conversa", like an
  #                incoming message: "Reabrir a mesma conversa" reopens it as
  #                pending; "Criar novas conversas" starts a new one
  #   none      -> create a new conversation as pending
  #
  # Either way the conversation ends up tied to this campaign and, when it has
  # no origin yet, takes "Disparo interno" (an origin already set wins).
  def build_campaign_conversation(contact_inbox)
    existing = inbox.conversations
                    .where(contact_id: contact_inbox.contact_id)
                    .then { |scope| inbox.lock_to_single_conversation? ? scope : scope.where.not(status: :resolved) }
                    .order(last_activity_at: :desc)
                    .first

    if existing
      existing.update!(campaign_link_attributes(existing))
      return existing
    end

    Conversation.create!(
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      campaign_id: campaign.id,
      origem: Contacts::OriginAttributionService::INTERNAL_CAMPAIGN,
      status: :pending
    )
  end

  def campaign_link_attributes(conversation)
    attributes = { campaign_id: campaign.id }
    attributes[:status] = :pending if conversation.resolved?
    attributes[:origem] = Contacts::OriginAttributionService::INTERNAL_CAMPAIGN if conversation.origem.blank?
    attributes
  end

  # Optional tag chosen when the campaign was created, so the team can find
  # later which conversations came from it. `add_labels` keeps whatever the
  # conversation already had.
  def apply_conversation_label(conversation)
    return if campaign.conversation_label.blank?

    conversation.add_labels(campaign.conversation_label)
  end

  def build_outgoing_template_message(conversation, content, template_params)
    Messages::MessageBuilder.new(
      campaign.sender,
      conversation,
      {
        content: content,
        message_type: 'outgoing',
        template_params: template_params,
        campaign_id: campaign.id
      }
    ).perform
  end
end
