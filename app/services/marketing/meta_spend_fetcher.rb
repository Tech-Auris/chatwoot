# Pulls daily ad spend from Meta Marketing API and upserts into
# `campaign_spends`. Runs per-account, called by the daily sync job.
#
# Endpoint: /act_{ad_account_id}/insights
#   * level=ad — one row per ad per day. Ad-level matches
#     `Conversation.campaign_referral.source_id` (which is the ad_id) so
#     the report can join without a mapping table.
#   * time_range={since,until} — daily windows for idempotency: today's
#     amount gets re-synced tomorrow with a fresh close (spend can grow
#     up to the ad account's timezone cutoff).
#   * time_increment=1 — force daily breakdown even for multi-day ranges.
#
# Requires the same access_token the CAPI integration uses AS LONG AS the
# operator granted the `ads_read` scope on the OAuth app. Without that scope
# Meta returns HTTP 400 with error code 200 — we mark the integration as
# permanently unhealthy in the log; the operator has to re-authorize.
class Marketing::MetaSpendFetcher
  META_API_VERSION = 'v20.0'.freeze
  DEFAULT_LOOKBACK_DAYS = 7
  MAX_LOOKBACK_DAYS = 90

  pattr_initialize [:account!, { lookback_days: DEFAULT_LOOKBACK_DAYS }]

  def perform
    integration = fetch_integration
    return failure('no active meta_capi integration') if integration.blank?
    return failure('meta integration missing ad_account_id') if integration.credentials['ad_account_id'].blank?

    rows = fetch_insights(integration)
    return failure(rows) if rows.is_a?(Hash) && rows[:error]

    upsert_rows!(rows, integration)
    { ok: true, rows_synced: rows.size }
  end

  private

  def fetch_integration
    account.marketing_integrations
           .where(status: %i[test_mode active])
           .find_by(provider: :meta_capi)
  end

  def fetch_insights(integration)
    since = safe_lookback_days.days.ago.to_date
    until_ = Time.zone.today

    response = HTTParty.get(
      "https://graph.facebook.com/#{META_API_VERSION}/act_#{integration.credentials['ad_account_id']}/insights",
      query: {
        level: 'ad',
        fields: 'ad_id,ad_name,campaign_id,campaign_name,spend,account_currency,date_start,date_stop',
        time_range: { since: since.iso8601, until: until_.iso8601 }.to_json,
        time_increment: 1,
        limit: 500,
        access_token: integration.credentials['access_token']
      },
      timeout: 15
    )

    return { error: "HTTP #{response.code}", body: safe_parse(response) } unless response.success?

    Array(safe_parse(response)['data'])
  end

  def upsert_rows!(rows, _integration)
    rows.each { |row| upsert_row!(row) }
  end

  def upsert_row!(row)
    amount_cents = (row['spend'].to_f * 100).round
    attrs = base_attrs_for(row).merge(
      amount_cents: amount_cents,
      currency: row['account_currency'] || 'BRL',
      last_synced_at: Time.current,
      external_metadata: row
    )
    scope = base_attrs_for(row)
    record = account.campaign_spends.find_or_initialize_by(**scope)
    record.assign_attributes(attrs)
    record.save!
  end

  def base_attrs_for(row)
    {
      provider: :meta,
      source_id: row['ad_id'].to_s,
      source_type: 'meta_ad',
      period_start: Date.parse(row['date_start']),
      period_end: Date.parse(row['date_stop'])
    }
  end

  def safe_parse(response)
    response.parsed_response.is_a?(Hash) ? response.parsed_response : { 'raw_body' => response.body.to_s }
  end

  def safe_lookback_days
    lookback_days.to_i.clamp(1, MAX_LOOKBACK_DAYS)
  end

  def failure(reason)
    Rails.logger.warn("[MetaSpendFetcher] account ##{account.id} — #{reason}")
    { ok: false, reason: reason }
  end
end
