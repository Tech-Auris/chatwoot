# Creates the kit's follow-up templates (auris_fup_*) on the channel's WABA
# right after a Cloud number is connected, so the n8n follow-up can go out of
# the 24h window from day one. Skips any template the WABA already has with
# the same name and language, so reconnecting never duplicates, and shares
# the result with the other numbers on the same WABA.
class Whatsapp::InstallFollowUpTemplatesJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return unless channel.provider == 'whatsapp_cloud'

    channel.sync_templates
    existing = Array(channel.reload.message_templates).filter_map { |t| [t['name'], t['language']] if t.is_a?(Hash) }

    Whatsapp::TemplateKit.follow_up.each do |template|
      next if existing.include?([template['name'], Whatsapp::TemplateKit::LANGUAGE])

      install(channel, template)
    end
    channel.sync_templates
    channel.share_templates_with_siblings
  end

  private

  # Meta's "content in this language already exists": another number on the
  # same WABA installed it first, which is what we wanted.
  ALREADY_EXISTS_SUBCODE = 2_388_024

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
end
