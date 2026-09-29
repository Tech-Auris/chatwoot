# Pulls daily ad spend from Meta Marketing API and upserts into
# `campaign_spends`, for every enabled ad account of the account's Meta
# integration (the grid in Marketing → Pixel e Dados). Called by the daily
# sync job and by the grid's "Sincronizar agora".
#
# Endpoint: /act_{ad_account_id}/insights
#   * level=ad — one row per ad per day. Ad-level matches
#     `Conversation.campaign_referral.source_id` (which is the ad_id) so
#     the report can join without a mapping table.
#   * time_range={since,until} — daily windows for idempotency: today's
#     amount gets re-synced tomorrow with a fresh close (spend can grow
#     up to the ad account's timezone cutoff).
#   * time_increment=1 — force daily breakdown even for multi-day ranges.
#   * paged through `paging.next`: a busy account over 90 days easily passes
#     one page.
#
# Uses the integration's `ads_read_token` when set, else the CAPI
# `access_token` — either way it needs the `ads_read` scope on each ad
# account. Each account records its own outcome (rows or the Meta error), so
# one account losing access doesn't stop the others.
class Marketing::MetaSpendFetcher
  META_API_VERSION = 'v20.0'.freeze
  DEFAULT_LOOKBACK_DAYS = 7
  MAX_LOOKBACK_DAYS = 90
  MAX_PAGES = 50

  class FetchError < StandardError; end

  pattr_initialize [:account!, { lookback_days: DEFAULT_LOOKBACK_DAYS }]

  def perform
    integration = fetch_integration
    return failure('no active meta_capi integration') if integration.blank?

    integration.import_legacy_ad_account!
    ad_accounts = integration.ad_accounts.enabled.to_a
    return failure('meta integration has no ad account (ad_account_id)') if ad_accounts.empty?

    results = ad_accounts.map { |ad_account| sync_ad_account(integration, ad_account) }
    { ok: results.all? { |result| result[:ok] }, rows_synced: results.sum { |result| result[:rows_synced].to_i }, accounts: results }
  end

  private

  def fetch_integration
    account.marketing_integrations
           .where(status: %i[test_mode active])
           .find_by(provider: :meta_capi)
  end

  def sync_ad_account(integration, ad_account)
    rows = fetch_insights(integration, ad_account)
    rows.each { |row| upsert_row!(row) }
    ad_account.record_sync!(rows_synced: rows.size)
    { ad_account_id: ad_account.external_id, ok: true, rows_synced: rows.size }
  rescue FetchError => e
    ad_account.record_sync_error!(e.message)
    failure("act_#{ad_account.external_id} — #{e.message}").merge(ad_account_id: ad_account.external_id)
  end

  def fetch_insights(integration, ad_account)
    url = "https://graph.facebook.com/#{META_API_VERSION}/act_#{ad_account.external_id}/insights"
    query = insights_query(integration)
    rows = []

    MAX_PAGES.times do
      body = get_page(url, query)
      rows.concat(Array(body['data']))
      url = body.dig('paging', 'next')
      break if url.blank?

      query = nil # the `next` url already carries every parameter
    end
    rows
  end

  def insights_query(integration)
    {
      level: 'ad',
      fields: 'account_id,ad_id,ad_name,campaign_id,campaign_name,spend,account_currency,date_start,date_stop',
      time_range: { since: safe_lookback_days.days.ago.to_date.iso8601, until: Time.zone.today.iso8601 }.to_json,
      time_increment: 1,
      limit: 500,
      access_token: integration.ads_read_access_token
    }
  end

  def get_page(url, query)
    response = HTTParty.get(url, query: query, timeout: 15)
    body = safe_parse(response)
    raise FetchError, (body.dig('error', 'message') || "HTTP #{response.code}") unless response.success?

    body
  end

  def upsert_row!(row)
    attrs = base_attrs_for(row).merge(
      amount_cents: (row['spend'].to_f * 100).round,
      currency: row['account_currency'] || 'BRL',
      last_synced_at: Time.current,
      external_metadata: row
    )
    record = account.campaign_spends.find_or_initialize_by(**base_attrs_for(row))
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
