# Sends a single `ConversionEventDispatch` to Meta's Conversions API.
# Called from `MarketingConversionDispatchJob` (Sidekiq exponential backoff),
# so transient failures re-raise for the job to retry; permanent failures
# (invalid access token, missing pixel, etc.) mark the dispatch
# `permanently_failed` and swallow the error.
#
# Payload contract for click-to-messaging conversions (per Meta CAPI docs):
#   * action_source: "business_messaging"
#   * messaging_channel: "whatsapp" | "instagram" | "messenger"
#   * user_data.ctwa_clid — the click token we captured on the first inbound
#     (Cloud + Baileys), the same field that lets Meta close the loop back
#     to the ad. Falls back to nil for organic contacts.
#   * user_data.em / ph — SHA256 of lowercased-trimmed email / normalized
#     phone. Only ever in memory; never persisted in the raw form.
#
# Idempotency: Meta dedupes by `event_id` within a 7-day window, so a Sidekiq
# retry of the same dispatch (identical event_id) is safe on their side too.
class Marketing::MetaCapiDispatcher
  META_API_VERSION = 'v20.0'.freeze

  # Error subcodes Meta returns that are NOT worth retrying — token is
  # invalid, pixel doesn't exist, request malformed. Everything else
  # (rate limits, 5xx, network) re-raises for Sidekiq's exponential
  # backoff to catch. See https://developers.facebook.com/docs/marketing-api/error-reference
  PERMANENT_ERROR_CODES = [100, 190, 803, 2500].freeze

  MESSAGING_CHANNEL_BY_TYPE = {
    'Channel::Whatsapp' => 'whatsapp',
    'Channel::Instagram' => 'instagram',
    'Channel::FacebookPage' => 'messenger'
  }.freeze

  pattr_initialize [:dispatch!]

  def perform
    return if dispatch.sent?

    integration = fetch_integration
    return mark_permanently_failed!(reason: 'no active meta_capi integration') if integration.blank?

    payload = build_payload(integration)
    dispatch.update!(payload: payload, attempts: dispatch.attempts + 1, last_attempted_at: Time.current)

    response = post_to_meta(integration, payload)
    handle_response(response)
  end

  private

  def fetch_integration
    dispatch.account.marketing_integrations
            .where(status: %i[test_mode active])
            .find_by(provider: :meta_capi)
  end

  # `data` is an array so we could batch someday. For now we always send
  # exactly one event per dispatch — retries stay simple.
  def build_payload(integration)
    body = { data: [event_hash], partner_agent: 'aurischat-capi/1.0' }
    body[:test_event_code] = integration.credentials['test_event_code'] if send_as_test_event?(integration)
    body
  end

  def event_hash
    {
      event_name: dispatch.conversion_event.meta_event_name,
      event_time: dispatch.created_at.to_i,
      event_id: dispatch.event_id,
      action_source: 'business_messaging',
      messaging_channel: messaging_channel,
      user_data: user_data
    }
  end

  # test_event_code makes events show up in Meta Events Manager's Test Events
  # tab instead of the real feed — the operator flips the integration to
  # `active` once they've watched the test events land.
  def send_as_test_event?(integration)
    integration.test_mode? && integration.credentials['test_event_code'].present?
  end

  def messaging_channel
    MESSAGING_CHANNEL_BY_TYPE[dispatch.conversation.inbox.channel_type]
  end

  def user_data
    contact = dispatch.conversation.contact
    referral = dispatch.conversation.additional_attributes.is_a?(Hash) ? dispatch.conversation.additional_attributes['campaign_referral'] : nil
    referral ||= {}

    {
      em: hashed_emails(contact),
      ph: hashed_phones(contact),
      ctwa_clid: referral['ctwa_clid']
    }.compact
  end

  def hashed_emails(contact)
    return nil if contact.email.blank?

    [sha256(contact.email.downcase.strip)]
  end

  # Meta expects phone digits only (no +, no formatting). Contact numbers are
  # stored E.164 with a leading +; strip everything except digits.
  def hashed_phones(contact)
    return nil if contact.phone_number.blank?

    digits = contact.phone_number.gsub(/\D/, '')
    return nil if digits.blank?

    [sha256(digits)]
  end

  def sha256(value)
    Digest::SHA256.hexdigest(value)
  end

  def post_to_meta(integration, payload)
    pixel_id = integration.credentials['pixel_id']
    access_token = integration.credentials['access_token']

    HTTParty.post(
      "https://graph.facebook.com/#{META_API_VERSION}/#{pixel_id}/events",
      body: payload.merge(access_token: access_token).to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )
  end

  def handle_response(response)
    parsed = safe_parse(response)
    dispatch.update!(response: parsed)

    return dispatch.update!(status: :sent) if response.success?
    return mark_permanently_failed!(reason: parsed) if permanent_error?(parsed)

    dispatch.update!(status: :failed)
    raise "Meta CAPI transient error (HTTP #{response.code}): #{parsed.inspect}"
  end

  def safe_parse(response)
    return { 'raw_body' => response.body.to_s } if response.parsed_response.nil?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : { 'raw_body' => response.body.to_s }
  end

  def permanent_error?(parsed)
    return false unless parsed.is_a?(Hash)

    code = parsed.dig('error', 'code').to_i
    PERMANENT_ERROR_CODES.include?(code)
  end

  def mark_permanently_failed!(reason:)
    payload = { permanently_failed_reason: reason }
    dispatch.update!(status: :permanently_failed, response: dispatch.response.merge(payload))
  end
end
