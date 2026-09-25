# Reads the event names the account's Meta pixel actually receives, so the
# "Nome do evento no Meta" input on the conversion-event form can suggest
# real values instead of leaving the operator to remember the exact spelling
# of what the BM configured.
#
# The list is a merge of:
#   * `STANDARD_EVENTS` — the fixed catalog Meta ships for the Server Events
#     API. Always present, even when the pixel hasn't seen any traffic yet.
#   * `custom` — event names the pixel has actually received in the last
#     30 days, as reported by `/{pixel-id}/stats?aggregation=event`. Only
#     the names that aren't already in the standard catalog land here.
#
# Errors from Meta (network, expired token, revoked permission) are
# swallowed so the form still opens with the standard list — a broken
# Meta call must not lock the operator out of saving a conversion event.
class Marketing::MetaPixelEventsService
  META_API_VERSION = 'v20.0'.freeze
  LOOKBACK = 30.days
  # Server-side Standard Events per Meta CAPI docs (2026-01). If Meta adds
  # or renames one, land it here — the frontend reads this list verbatim
  # into the suggestions.
  # https://developers.facebook.com/docs/meta-pixel/reference#standard-events
  STANDARD_EVENTS = %w[
    AddPaymentInfo AddToCart AddToWishlist CompleteRegistration Contact
    CustomizeProduct Donate FindLocation InitiateCheckout Lead
    PageView Purchase Schedule Search StartTrial SubmitApplication
    Subscribe ViewContent
  ].freeze

  def initialize(integration:)
    @integration = integration
  end

  def perform
    { standard: STANDARD_EVENTS, custom: recent_custom_events }
  end

  private

  attr_reader :integration

  def recent_custom_events
    return [] unless integration&.meta_capi?

    pixel_id = integration.credentials['pixel_id']
    access_token = integration.credentials['access_token']
    return [] if pixel_id.blank? || access_token.blank?

    response = HTTParty.get(
      "https://graph.facebook.com/#{META_API_VERSION}/#{pixel_id}/stats",
      query: { aggregation: 'event', start_time: LOOKBACK.ago.to_i, access_token: access_token },
      timeout: 5
    )
    return [] unless response.code.to_i == 200

    extract_event_names(response.parsed_response) - STANDARD_EVENTS
  rescue StandardError => e
    Rails.logger.warn("[meta pixel events] #{e.class}: #{e.message}")
    []
  end

  # `/pixel/stats` returns `{ data: [{ data: { <event_name>: <count>, ... }, ... }] }`.
  # Different aggregation windows can shape the array differently, so pull every
  # key we find and dedupe.
  def extract_event_names(payload)
    Array(payload && payload['data']).flat_map do |bucket|
      inner = bucket['data']
      inner.is_a?(Hash) ? inner.keys : []
    end.uniq
  end
end
