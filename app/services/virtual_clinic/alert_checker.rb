# Runs the alert rules of one account (VirtualClinic::AlertsJob, every 15
# minutes) and raises the hand of the AI teammate when one fires: the alert
# is stored, administrators and managers get it in the notifications, and
# open maps update. The same rule does not fire again within its cooldown.
class VirtualClinic::AlertChecker
  RULES = [
    VirtualClinic::Alerts::WaitingPatients,
    VirtualClinic::Alerts::SilentInboxes,
    VirtualClinic::Alerts::FailedFollowUps,
    VirtualClinic::Alerts::ConversionDrop,
    VirtualClinic::Alerts::NoShowRate,
    VirtualClinic::Alerts::SeasonalPack
  ].freeze

  def initialize(account, rules: RULES)
    @account = account
    @rules = rules
  end

  def perform
    # Notifications are written in the clinic's language.
    I18n.with_locale(@account.locale) { @rules.each { |rule_class| check(rule_class.new(@account)) } }
  end

  private

  def check(rule)
    return unless rule.due?
    return if @account.virtual_clinic_alerts.exists?(rule: rule.class.key, created_at: rule.class::COOLDOWN.ago..)

    payload = rule.payload
    raise_hand(rule, payload) if payload
  end

  def raise_hand(rule, payload)
    alert = @account.virtual_clinic_alerts.create!(persona: rule.persona, rule: rule.class.key, payload: payload)
    users = @account.account_users.where(role: %i[administrator manager]).includes(:user).map(&:user)
    users.each do |user|
      NotificationBuilder.new(notification_type: 'virtual_clinic_alert', user: user, account: @account, primary_actor: alert).perform
    end
    VirtualClinic::AlertBroadcast.new(@account, users).perform
  end
end
