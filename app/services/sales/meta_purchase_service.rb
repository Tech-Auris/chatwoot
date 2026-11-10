# Tells Meta that a sale was paid: a Purchase on Auris's own pixel (Super
# Admin → Settings → Commercial), sent through the Conversions API because the
# payment is confirmed by Stripe, AsaaS or Inter, not in the buyer's browser.
#
# The ad click comes from the ClickUp lead's FBCLID, snapshotted on the quote,
# as `fbc`. The buyer's e-mail, phone and name go hashed. The value is the
# contract total. `event_id` is fixed per quote, so a retry is deduped by Meta.
class Sales::MetaPurchaseService
  META_API_VERSION = 'v20.0'.freeze
  PIXEL_CONFIG = 'COMMERCIAL_META_PIXEL_ID'.freeze
  TOKEN_CONFIG = 'COMMERCIAL_META_CAPI_TOKEN'.freeze
  TEST_CODE_CONFIG = 'COMMERCIAL_META_TEST_EVENT_CODE'.freeze
  TIMEOUT = 15

  class DeliveryError < StandardError; end

  pattr_initialize [:quote!, :paid_at!]

  def perform
    return unless configured?

    response = HTTParty.post(endpoint, body: payload.merge(access_token: token).to_json,
                                       headers: { 'Content-Type' => 'application/json' }, timeout: TIMEOUT)
    raise DeliveryError, "HTTP #{response.code}: #{response.body.to_s.truncate(300)}" unless response.success?

    quote.events.create!(event: 'meta_purchase_sent', metadata: { event_id: event_id, response: response.parsed_response })
  end

  def payload
    body = { data: [event] }
    body[:test_event_code] = test_event_code if test_event_code.present?
    body
  end

  private

  def configured?
    pixel_id.present? && token.present?
  end

  def event
    {
      event_name: 'Purchase',
      event_time: paid_at.to_i,
      event_id: event_id,
      user_data: user_data,
      custom_data: { value: quote.effective_charge_amount / 100.0, currency: quote.currency.upcase, content_name: content_name }
    }.merge(source)
  end

  def event_id
    "sales_quote_#{quote.id}_purchase"
  end

  # A payment the prospect started on the proposal page is a website event;
  # one registered by hand in Super Admin has no browser behind it.
  def source
    return { action_source: 'system_generated' } if quote.client_user_agent.blank?

    { action_source: 'website', event_source_url: Sales::ReservationMessageBuilder.public_url_for(quote) }.compact
  end

  def user_data
    buyer.merge(fbc: fbc, client_ip_address: quote.client_ip, client_user_agent: quote.client_user_agent).compact
  end

  def buyer
    {
      em: hashed(quote.prospect_email.to_s.downcase.strip),
      ph: hashed(quote.prospect_phone.to_s.gsub(/\D/, '')),
      fn: hashed(name_parts.first),
      ln: hashed(name_parts.drop(1).last),
      external_id: hashed(quote.id.to_s)
    }
  end

  # Meta's click cookie format: fb.<subdomain index>.<click time in ms>.<fbclid>.
  def fbc
    return if quote.fbclid.blank?

    captured_at = quote.fbclid_captured_at || quote.created_at
    "fb.1.#{(captured_at.to_f * 1000).to_i}.#{quote.fbclid}"
  end

  def name_parts
    @name_parts ||= quote.prospect_name.to_s.downcase.split
  end

  def hashed(value)
    return if value.blank?

    [Digest::SHA256.hexdigest(value)]
  end

  def content_name
    plan = quote.items.find(&:kind_plan?)
    [plan&.name, quote.billing_cycle].compact.join(' - ').presence
  end

  def endpoint
    "https://graph.facebook.com/#{META_API_VERSION}/#{pixel_id}/events"
  end

  def pixel_id
    @pixel_id ||= GlobalConfigService.load(PIXEL_CONFIG, '').to_s.strip
  end

  def token
    @token ||= GlobalConfigService.load(TOKEN_CONFIG, '').to_s.strip
  end

  def test_event_code
    @test_event_code ||= GlobalConfigService.load(TEST_CODE_CONFIG, '').to_s.strip
  end
end
