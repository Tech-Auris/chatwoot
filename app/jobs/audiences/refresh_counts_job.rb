# Keeps the size shown in Marketing → Públicos current for dynamic audiences,
# whose members change with their conversations, so the panel never has to
# count every audience on load. Static ones only change by hand and are
# recounted then.
class Audiences::RefreshCountsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Audience.dynamic.find_each do |audience|
      audience.refresh_count!
    rescue StandardError => e
      Rails.logger.warn("[Audiences::RefreshCountsJob] audience=#{audience.id}: #{e.class}: #{e.message}")
    end
  end
end
