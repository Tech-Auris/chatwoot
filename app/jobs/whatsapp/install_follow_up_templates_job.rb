# Creates the kit's follow-up templates (auris_fup_*) on the channel's WABA
# right after a Cloud number is connected, so the n8n follow-up can go out of
# the 24h window from day one. Skips any template the WABA already has with
# the same name and language, so reconnecting never duplicates, and shares
# the result with the other numbers on the same WABA.
class Whatsapp::InstallFollowUpTemplatesJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return {} unless channel.provider == 'whatsapp_cloud'

    channel.sync_templates
    missing = Whatsapp::TemplateKit.follow_up.reject { |template| installed?(channel, template) }
    return {} if missing.empty?

    results = missing.index_with { |template| install(channel, template) }
    channel.sync_templates
    channel.share_templates_with_siblings
    cache_created(channel, results.select { |_, result| result[:success] })
    results.reject { |_, result| result[:success] }.to_h { |template, result| [template['name'], result[:error_message]] }
  end

  private

  # Meta's "content in this language already exists": another number on the
  # same WABA installed it first, which is what we wanted.
  ALREADY_EXISTS_SUBCODE = 2_388_024
  def installed?(channel, template)
    Array(channel.reload.message_templates).any? do |cached|
      cached.is_a?(Hash) && cached['name'] == template['name'] && cached['language'] == Whatsapp::TemplateKit::LANGUAGE
    end
  end

  def install(channel, template)
    result = channel.provider_service.create_template(Whatsapp::TemplateKit.meta_payload(template))
    result = { success: true } if result[:error_subcode] == ALREADY_EXISTS_SUBCODE
    if result[:success]
      Rails.logger.info("[TemplateKit] account=#{channel.account_id} channel=#{channel.id} installed #{template['name']}")
    else
      Rails.logger.warn("[TemplateKit] account=#{channel.account_id} channel=#{channel.id} #{template['name']} failed: " \
                        "#{result[:error_message]} #{result[:error_details]}")
    end
    result
  end

  # Meta's list is eventually consistent: the sync right after a create may
  # not return it yet, so keep what the create answered until the next sync.
  def cache_created(channel, created)
    pending = created.reject { |template, _| installed?(channel, template) }
                     .map { |template, result| Whatsapp::TemplateKit.meta_payload(template).merge(result[:template] || {}) }
    return if pending.empty?

    cached = Array(channel.message_templates).select { |t| t.is_a?(Hash) }
    channel.update_columns(message_templates: pending + cached, message_templates_last_updated: Time.now.utc) # rubocop:disable Rails/SkipsModelValidations
  end
end
