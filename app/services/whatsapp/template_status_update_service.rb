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

    apply_status_change(templates, idx)
  end

  private

  def template_id
    @event_value[:message_template_id]
  end

  def new_status
    @event_value[:event]
  end

  # Meta sometimes replays the same event (webhook retries, no real
  # transition). Persist nothing and stay silent on those — otherwise
  # every replay would toast the operator again.
  def apply_status_change(templates, idx)
    previous_status = templates[idx]['status']
    return if previous_status.to_s == new_status.to_s

    templates[idx]['status'] = new_status
    @channel.update!(message_templates: templates, message_templates_last_updated: Time.now.utc)
    broadcast_status_change(templates[idx], previous_status)
  end

  def trigger_full_sync
    Rails.logger.info(
      "[whatsapp] template_status_update for unknown id=#{template_id} on channel=#{@channel.id} — kicking full sync"
    )
    Channels::Whatsapp::TemplatesSyncJob.perform_later(@channel)
  end

  # Fires an account-wide ActionCable event so open dashboards can show a
  # toast the moment Meta approves / rejects / pauses a template — no page
  # reload, no need to click Sync. Payload matches the shape the frontend
  # listener in dashboard/helper/actionCable.js expects (event + data).
  def broadcast_status_change(template, previous_status)
    ActionCable.server.broadcast(
      "account_#{@channel.account_id}",
      {
        event: 'meta_template.status_updated',
        data: {
          account_id: @channel.account_id,
          inbox_id: @channel.inbox.id,
          inbox_name: @channel.inbox.name,
          template_id: template['id'],
          template_name: template['name'],
          template_language: template['language'],
          previous_status: previous_status,
          new_status: new_status,
          reason: @event_value[:reason]
        }
      }
    )
  end
end
