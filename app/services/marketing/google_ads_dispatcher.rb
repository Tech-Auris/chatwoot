# Sends a single `ConversionEventDispatch` to Google Ads via the
# uploadClickConversions endpoint (Enhanced Conversions for Leads).
#
# Google needs an OAuth2 access token for every call. We keep only the
# long-lived refresh token in `credentials` and swap it for a short-lived
# access token on each dispatch — the extra HTTP round-trip is trivial
# compared to the tokens' 1h lifetime and it keeps us stateless.
#
# The `developer_token` is per-account (not Auris-wide) so agencies can
# swap in their own; the OAuth app credentials, on the other hand, are
# Auris-owned and read from env — every clinic authorises against the
# same OAuth app.
#
# gclid resolution:
#   1. `conversation.additional_attributes.campaign_referral.gclid`
#      (kept in sync with the CTWA path — for a Google-attributed
#      conversation there is no CTWA, but future landing snippets could
#      populate it here).
#   2. First incoming message body scanned by
#      `CampaignReferralExtractor.gclid_from_body` — this is how the
#      site snippet delivers the click id today.
# No gclid ⇒ dispatch is `permanently_failed` (Google needs it to
# attribute the conversion; without it the upload is pointless).
class Marketing::GoogleAdsDispatcher
  GOOGLE_ADS_API_VERSION = 'v20'.freeze
  OAUTH_ENDPOINT = 'https://oauth2.googleapis.com/token'.freeze

  # Response codes we treat as permanent — invalid credentials, unknown
  # conversion action, permission problems. Everything else re-raises for
  # Sidekiq's default exponential backoff.
  PERMANENT_HTTP_STATUS = [400, 401, 403, 404].freeze

  pattr_initialize [:dispatch!]

  def perform
    return if dispatch.sent?

    integration = fetch_integration
    return mark_permanently_failed!(reason: 'no active google_ads_enhanced integration') if integration.blank?

    gclid = resolve_gclid
    return mark_permanently_failed!(reason: 'no gclid found on conversation or its messages') if gclid.blank?

    access_token = exchange_refresh_token!(integration)
    payload = build_payload(integration, gclid)
    dispatch.update!(payload: payload, attempts: dispatch.attempts + 1, last_attempted_at: Time.current)

    response = post_to_google(integration, access_token, payload)
    handle_response(response)
  end

  private

  def fetch_integration
    dispatch.account.marketing_integrations
            .where(status: %i[test_mode active])
            .find_by(provider: :google_ads_enhanced)
  end

  # Google's offline conversion upload wants a `gclid` — the click id the
  # site snippet forwarded through the WhatsApp text. We reuse the same
  # extractor the origem service uses so the behaviour stays consistent.
  def resolve_gclid
    referral_gclid = dispatch.conversation.additional_attributes.is_a?(Hash) &&
                     dispatch.conversation.additional_attributes.dig('campaign_referral', 'gclid')
    return referral_gclid if referral_gclid.present?

    first_incoming = dispatch.conversation.messages.incoming.order(:created_at).first
    ::CampaignReferralExtractor.gclid_from_body(first_incoming&.content)
  end

  def exchange_refresh_token!(integration)
    response = HTTParty.post(
      OAUTH_ENDPOINT,
      body: {
        client_id: ENV.fetch('GOOGLE_ADS_OAUTH_CLIENT_ID'),
        client_secret: ENV.fetch('GOOGLE_ADS_OAUTH_CLIENT_SECRET'),
        refresh_token: integration.credentials['oauth_refresh_token'],
        grant_type: 'refresh_token'
      },
      timeout: 10
    )
    raise "Google OAuth refresh failed (HTTP #{response.code}): #{response.body}" unless response.success?

    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : JSON.parse(response.body)
    parsed['access_token']
  end

  # Enhanced Conversions for Leads: PII goes in `userIdentifiers` as SHA256
  # hashes. Same hashing rules as Meta (lower-trim email, digits-only phone).
  def build_payload(integration, gclid)
    conversion = {
      gclid: gclid,
      conversionAction: "customers/#{integration.credentials['customer_id']}/conversionActions/#{integration.credentials['conversion_action_id']}",
      conversionDateTime: format_conversion_time(dispatch.created_at),
      userIdentifiers: user_identifiers
    }.compact

    { conversions: [conversion], partialFailure: true }
  end

  # Google accepts multiple identifiers; we always send email + phone when
  # available. Every identifier stays SHA256-hashed in-memory so the raw
  # values never touch `dispatch.payload`.
  def user_identifiers
    contact = dispatch.conversation.contact
    identifiers = []
    identifiers << { hashedEmail: sha256(contact.email.downcase.strip) } if contact.email.present?
    if contact.phone_number.present?
      digits = contact.phone_number.gsub(/\D/, '')
      identifiers << { hashedPhoneNumber: sha256(digits) } if digits.present?
    end
    identifiers.presence
  end

  def sha256(value)
    Digest::SHA256.hexdigest(value)
  end

  # Google Ads wants "YYYY-MM-DD HH:MM:SS+TZ" with a timezone offset.
  def format_conversion_time(time)
    time.strftime('%Y-%m-%d %H:%M:%S%z').sub(/(\d{2})(\d{2})$/, '\1:\2')
  end

  def post_to_google(integration, access_token, payload)
    headers = {
      'Authorization' => "Bearer #{access_token}",
      'developer-token' => integration.credentials['developer_token'],
      'Content-Type' => 'application/json'
    }
    headers['login-customer-id'] = integration.credentials['login_customer_id'] if integration.credentials['login_customer_id'].present?

    HTTParty.post(
      "https://googleads.googleapis.com/#{GOOGLE_ADS_API_VERSION}/customers/#{integration.credentials['customer_id']}:uploadClickConversions",
      body: payload.to_json,
      headers: headers,
      timeout: 10
    )
  end

  def handle_response(response)
    parsed = safe_parse(response)
    dispatch.update!(response: parsed)

    return dispatch.update!(status: :sent) if response.success? && !partial_failure?(parsed)
    return mark_permanently_failed!(reason: parsed) if PERMANENT_HTTP_STATUS.include?(response.code) || partial_failure?(parsed)

    dispatch.update!(status: :failed)
    raise "Google Ads transient error (HTTP #{response.code}): #{parsed.inspect}"
  end

  # `partialFailure: true` on the request means Google returns 200 with per-
  # row errors under `partialFailureError`. Treat those as permanent — the
  # payload was rejected (invalid gclid, hashed value format, etc.), not
  # transient.
  def partial_failure?(parsed)
    parsed.is_a?(Hash) && parsed['partialFailureError'].present?
  end

  def safe_parse(response)
    return { 'raw_body' => response.body.to_s } if response.parsed_response.nil?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : { 'raw_body' => response.body.to_s }
  end

  def mark_permanently_failed!(reason:)
    dispatch.update!(status: :permanently_failed, response: dispatch.response.merge('permanently_failed_reason' => reason))
  end
end
