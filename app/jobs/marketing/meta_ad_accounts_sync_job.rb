# "Sincronizar agora" on the ad accounts grid: the same pull the daily job
# does, for one account, over the last 30 days so a newly added ad account
# fills the reports right away. Each ad account records its own outcome.
class Marketing::MetaAdAccountsSyncJob < ApplicationJob
  queue_as :default

  LOOKBACK_DAYS = 30

  def perform(account_id)
    Marketing::MetaSpendFetcher.new(account: Account.find(account_id), lookback_days: LOOKBACK_DAYS).perform
  end
end
