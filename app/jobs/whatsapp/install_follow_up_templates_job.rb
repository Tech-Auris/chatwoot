# Creates the kit's follow-up templates (auris_fup_*, in every language) on the channel's WABA
# right after a Cloud number is connected, so the n8n follow-up can go out of
# the 24h window from day one. Skips any template the WABA already has with
# the same name and language, so reconnecting never duplicates, and shares
# the result with the other numbers on the same WABA.
class Whatsapp::InstallFollowUpTemplatesJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return {} unless channel.provider == 'whatsapp_cloud'

    channel.sync_templates
    missing = Whatsapp::TemplateKit.follow_up_payloads.reject { |payload| installed?(channel, payload) }
    return {} if missing.empty?

    results = missing.index_with { |payload| install(channel, payload) }
    channel.sync_templates
    channel.share_templates_with_siblings
    cache_created(channel, results.select { |_, result| result[:success] })
    results.reject { |_, result| result[:success] }.to_h { |payload, result| [label(payload), result[:error_message]] }
  end

  private

  # Meta's "content in this language already exists": another number on the
  # same WABA installed it first, which is what we wanted.
  ALREADY_EXISTS_SUBCODE = 2_388_024
  def installed?(channel, payload)
    Array(channel.reload.message_templates).any? do |cached|
      cached.is_a?(Hash) && cached['name'] == payload['name'] && cached['language'] == payload['language']
    end
  end

  def label(payload)
    payload['language'] == Whatsapp::TemplateKit::LANGUAGE ? payload['name'] : "#{payload['name']} (#{payload['language']})"
  end

  def install(channel, payload)
    result = channel.provider_service.create_template(payload)
    result = { success: true } if result[:error_subcode] == ALREADY_EXISTS_SUBCODE
    if result[:success]
      Rails.logger.info("[TemplateKit] account=#{channel.account_id} channel=#{channel.id} installed #{label(payload)}")
    else
      Rails.logger.warn("[TemplateKit] account=#{channel.account_id} channel=#{channel.id} #{label(payload)} failed: " \
                        "#{result[:error_message]} #{result[:error_details]}")
    end
    result
  end

  # Meta's list is eventually consistent: the sync right after a create may
  # not return it yet, so keep what the create answered until the next sync.
  def cache_created(channel, created)
    pending = created.reject { |payload, _| installed?(channel, payload) }
                     .map { |payload, result| payload.merge(result[:template] || {}) }
    return if pending.empty?

    cached = Array(channel.message_templates).select { |t| t.is_a?(Hash) }
    channel.update_columns(message_templates: pending + cached, message_templates_last_updated: Time.now.utc) # rubocop:disable Rails/SkipsModelValidations
  end
end
