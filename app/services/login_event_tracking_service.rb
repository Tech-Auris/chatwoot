# Records one LoginEvent per (login, account) after every successful
# authentication. Called from `DeviseOverrides::SessionsController` right
# after `UserSessionTrackingService`, so the same UA parsing and IP-lookup
# pipeline enriches the row.
#
# Failures are swallowed and logged — a broken audit trail must never
# refuse a login.
class LoginEventTrackingService
  LEGACY_MOBILE_UAS = UserSessionTrackingService.const_get(:LEGACY_MOBILE_UAS, false)
  private_constant :LEGACY_MOBILE_UAS

  def initialize(user:, request:)
    @user = user
    @request = request
  end

  # Fans out one row per account membership; users with none get a single
  # row with account_id / role null so the login itself is still auditable.
  def perform
    memberships = @user.account_users.to_a
    if memberships.empty?
      persist(account_id: nil, role: nil)
    else
      memberships.each do |membership|
        persist(account_id: membership.account_id, role: membership.role_before_type_cast)
      end
    end
  end

  private

  def persist(account_id:, role:)
    event = LoginEvent.create!(base_attributes.merge(account_id: account_id, role: role))
    LoginEventIpLookupJob.perform_later(event) if event.ip_address.present? && event.city.blank?
    event
  end

  def base_attributes
    @base_attributes ||= begin
      browser = Browser.new(@request.user_agent)
      attrs = {
        user: @user,
        ip_address: @request.remote_ip,
        user_agent: @request.user_agent,
        browser_name: browser.name,
        browser_version: browser.full_version,
        device_name: browser.device.name,
        platform_name: browser.platform.name,
        platform_version: browser.platform.version
      }
      patch_for_legacy_mobile(attrs)
    end
  end

  def patch_for_legacy_mobile(attrs)
    return attrs unless attrs[:browser_name] == 'Unknown Browser'

    hit = LEGACY_MOBILE_UAS.find { |m| @request.user_agent.to_s.match?(m[:match]) }
    return attrs unless hit

    attrs.merge(
      browser_name: 'Chatwoot Mobile',
      browser_version: nil,
      platform_name: hit[:platform],
      platform_version: nil,
      device_name: hit[:device]
    )
  end
end
