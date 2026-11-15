# Rewrites the account's `cache_supabase_special_scenarios:{account_id}` in
# n8n's Redis, so a Super Admin edit reaches the secretary without waiting for
# the hourly `Atualiza Caches Supabase v2`. Without N8N_REDIS_URL it does
# nothing and the change only lands on that hourly run.
class SecretarySpecialScenarios::RefreshCacheJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    url = ENV.fetch('N8N_REDIS_URL', nil)
    return if url.blank?

    Redis.new(url: url).set("cache_supabase_special_scenarios:#{account_id}", JSON.generate(SecretarySpecialScenario.cache_payload(account_id)))
  end
end
