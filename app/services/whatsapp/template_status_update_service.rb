class Whatsapp::TemplateStatusUpdateService
  # Handles Meta's `message_template_status_update` webhook payload.
  # Patches the cached template entry in `channel.message_templates` so the
  # operator sees the fresh status (APPROVED / PENDING / REJECTED / PAUSED /
  # DISABLED / IN_APPEAL / FLAGGED) on the Meta Templates page after a page
  # reload — no need to click "Sincronizar" to re-fetch the whole catalog.
  #
  # When the template is not in the cache yet (e.g. Meta approved a
  # brand-new template we haven't fetched), we fall back to a full sync so
  # the row shows up next time — safer than persisting a partial entry that
  # would miss `components`, `language` etc.
  def initialize(channel, event_value)
    @channel = channel
    @event_value = event_value.with_indifferent_access
  end

  def perform
    return if @channel.blank? || template_id.blank? || new_status.blank?

    templates = Array(@channel.message_templates).map(&:deep_dup)
    idx = templates.index { |t| t['id'].to_s == template_id.to_s }

    return trigger_full_sync if idx.nil?

    templates[idx]['status'] = new_status
    @channel.update!(message_templates: templates, message_templates_last_updated: Time.now.utc)
  end

  private

  def template_id
    @event_value[:message_template_id]
  end

  def new_status
    @event_value[:event]
  end

  def trigger_full_sync
    Rails.logger.info(
      "[whatsapp] template_status_update for unknown id=#{template_id} on channel=#{@channel.id} — kicking full sync"
    )
    Channels::Whatsapp::TemplatesSyncJob.perform_later(@channel)
  end
end
