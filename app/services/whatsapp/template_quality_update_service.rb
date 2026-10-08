# Handles Meta's `message_template_quality_update` webhook: keeps the cached
# template's `quality_score` in the same shape the sync stores
# (`{ score:, date: }`), so every picker shows the new quality without a sync.
# A template not in the cache yet triggers a full sync, like status updates.
class Whatsapp::TemplateQualityUpdateService
  def initialize(channel, event_value)
    @channel = channel
    @event_value = event_value.with_indifferent_access
  end

  def perform
    return if @channel.blank? || template_id.blank? || new_score.blank?

    templates = Array(@channel.message_templates).map(&:deep_dup)
    template = templates.find { |t| t['id'].to_s == template_id.to_s }
    return Channels::Whatsapp::TemplatesSyncJob.perform_later(@channel) if template.nil?

    template['quality_score'] = { 'score' => new_score, 'date' => Time.current.to_i }
    # validate: false skips the remote credential re-check, which would call
    # Meta on every webhook and drop the update if it failed.
    @channel.assign_attributes(message_templates: templates, message_templates_last_updated: Time.now.utc)
    @channel.save!(validate: false)
  end

  private

  def template_id
    @event_value[:message_template_id]
  end

  def new_score
    @event_value[:new_quality_score]
  end
end
