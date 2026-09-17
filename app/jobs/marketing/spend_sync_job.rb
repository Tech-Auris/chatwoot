# Daily fan-out that walks every account with an active marketing integration
# and pulls the last 7 days of spend from each configured provider. Cron
# entry lives in config/schedule.yml; per-provider failures are logged but
# never abort the fan-out for the other accounts.
#
# 7-day rolling window: Meta and Google can revise today's numbers up to the
# ad account's timezone cutoff, and a delivery-side glitch on day D can push
# the correction to D+1 or D+2. Re-syncing the last week catches those and
# keeps last week's totals stable.
class Marketing::SpendSyncJob < ApplicationJob
  queue_as :low

  LOOKBACK_DAYS = 7

  def perform
    Account.joins(:marketing_integrations)
           .where(marketing_integrations: { status: %i[test_mode active] })
           .distinct
           .find_each { |account| sync_account(account) }
  end

  private

  def sync_account(account)
    sync_provider(account, :meta_capi, Marketing::MetaSpendFetcher)
    sync_provider(account, :google_ads_enhanced, Marketing::GoogleAdsSpendFetcher)
  end

  def sync_provider(account, provider, fetcher_class)
    return unless active_integration?(account, provider)

    fetcher_class.new(account: account, lookback_days: LOOKBACK_DAYS).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  def active_integration?(account, provider)
    account.marketing_integrations.exists?(status: %i[test_mode active], provider: provider)
  end
end
