# Async resolves an IP into city/country and back-fills the LoginEvent.
# Same pattern as `UserSessionIpLookupJob`; kept separate so a slow IP
# lookup never blocks the login path.
class LoginEventIpLookupJob < ApplicationJob
  queue_as :low

  def perform(event)
    return if event.ip_address.blank?

    result = IpLookupService.new.perform(event.ip_address)
    return unless result

    event.update_columns( # rubocop:disable Rails/SkipsModelValidations
      city: result.city,
      country: result.country,
      country_code: result.country_code
    )
  rescue StandardError => e
    Rails.logger.warn "LoginEventIpLookupJob failed: #{e.message}"
  end
end
