# Keeps the quality / account status of every official API number fresh for
# the badges in the "Via:" picker and the inbox grid (see
# Channel::Whatsapp#update_health_summary!). Opening "Saúde da conta" also
# refreshes the number on the spot.
class Channels::Whatsapp::HealthSummaryRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::Whatsapp.where(provider: 'whatsapp_cloud').find_each do |channel|
      Whatsapp::HealthService.new(channel).fetch_health_status
    rescue StandardError => e
      Rails.logger.warn "[WHATSAPP HEALTH] summary refresh failed for channel #{channel.id}: #{e.message}"
    end
  end
end
