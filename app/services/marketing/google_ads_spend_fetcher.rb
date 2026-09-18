# Pulls daily ad spend from Google Ads API and upserts into `campaign_spends`.
# Runs per-account, called by the daily sync job.
#
# Query: `SELECT campaign.id, campaign.name, metrics.cost_micros, segments.date
# FROM campaign WHERE segments.date DURING LAST_7_DAYS` — campaign-level
# because the Fase 1.5 gclid → conversion action mapping is campaign-scoped
# (there's no gclid attribution to a specific ad group ad inside Google Ads
# offline uploads).
#
# OAuth refresh mirrors Marketing::GoogleAdsDispatcher — same OAuth app
# whose credentials (GOOGLE_ADS_OAUTH_CLIENT_ID / GOOGLE_ADS_OAUTH_CLIENT_SECRET)
# live in InstallationConfig (super_admin) with ENV as fallback — and the same
# per-account refresh_token in `credentials.oauth_refresh_token`.
class Marketing::GoogleAdsSpendFetcher
  GOOGLE_ADS_API_VERSION = 'v20'.freeze
  OAUTH_ENDPOINT = 'https://oauth2.googleapis.com/token'.freeze
  DEFAULT_LOOKBACK_DAYS = 7
  MAX_LOOKBACK_DAYS = 90

  pattr_initialize [:account!, { lookback_days: DEFAULT_LOOKBACK_DAYS }]

  def perform
    integration = fetch_integration
    return failure('no active google_ads_enhanced integration') if integration.blank?

    access_token = refresh_access_token!(integration)
    rows = search_stream(integration, access_token)
    return failure(rows) if rows.is_a?(Hash) && rows[:error]

    upsert_rows!(rows)
    { ok: true, rows_synced: rows.size }
  rescue StandardError => e
    failure(e.message)
  end

  private

  def fetch_integration
    account.marketing_integrations
           .where(status: %i[test_mode active])
           .find_by(provider: :google_ads_enhanced)
  end

  def refresh_access_token!(integration)
    response = HTTParty.post(
      OAUTH_ENDPOINT,
      body: {
        client_id: GlobalConfigService.load('GOOGLE_ADS_OAUTH_CLIENT_ID', ENV.fetch('GOOGLE_ADS_OAUTH_CLIENT_ID', nil)),
        client_secret: GlobalConfigService.load('GOOGLE_ADS_OAUTH_CLIENT_SECRET', ENV.fetch('GOOGLE_ADS_OAUTH_CLIENT_SECRET', nil)),
        refresh_token: integration.credentials['oauth_refresh_token'],
        grant_type: 'refresh_token'
      },
      timeout: 10
    )
    raise "Google OAuth refresh failed (HTTP #{response.code}): #{response.body}" unless response.success?

    (response.parsed_response.is_a?(Hash) ? response.parsed_response : JSON.parse(response.body))['access_token']
  end

  def search_stream(integration, access_token)
    since = safe_lookback_days.days.ago.to_date
    until_ = Time.zone.today
    query = <<~GAQL.strip
      SELECT campaign.id, campaign.name, metrics.cost_micros, segments.date, customer.currency_code
      FROM campaign
      WHERE segments.date BETWEEN '#{since.iso8601}' AND '#{until_.iso8601}'
    GAQL

    response = HTTParty.post(
      "https://googleads.googleapis.com/#{GOOGLE_ADS_API_VERSION}/customers/#{integration.credentials['customer_id']}/googleAds:searchStream",
      body: { query: query }.to_json,
      headers: request_headers(integration, access_token),
      timeout: 15
    )
    return { error: "HTTP #{response.code}", body: safe_parse(response) } unless response.success?

    parsed = safe_parse(response)
    # searchStream returns an array of { results: [...] } chunks.
    Array(parsed).flat_map { |chunk| chunk['results'] || [] }
  end

  def request_headers(integration, access_token)
    headers = {
      'Authorization' => "Bearer #{access_token}",
      'developer-token' => integration.credentials['developer_token'],
      'Content-Type' => 'application/json'
    }
    headers['login-customer-id'] = integration.credentials['login_customer_id'] if integration.credentials['login_customer_id'].present?
    headers
  end

  def upsert_rows!(rows)
    rows.each { |row| upsert_row!(row) }
  end

  def upsert_row!(row)
    day = Date.parse(row.dig('segments', 'date'))
    record = account.campaign_spends.find_or_initialize_by(
      provider: :google_ads,
      source_id: row.dig('campaign', 'id').to_s,
      source_type: 'google_ads_campaign',
      period_start: day,
      period_end: day
    )
    record.assign_attributes(
      amount_cents: (row.dig('metrics', 'costMicros').to_i / 10_000), # micros → cents
      currency: row.dig('customer', 'currencyCode') || 'BRL',
      last_synced_at: Time.current,
      external_metadata: row
    )
    record.save!
  end

  def safe_parse(response)
    return { 'raw_body' => response.body.to_s } if response.parsed_response.nil?

    response.parsed_response
  end

  def safe_lookback_days
    lookback_days.to_i.clamp(1, MAX_LOOKBACK_DAYS)
  end

  def failure(reason)
    Rails.logger.warn("[GoogleAdsSpendFetcher] account ##{account.id} — #{reason.inspect}")
    { ok: false, reason: reason }
  end
end
