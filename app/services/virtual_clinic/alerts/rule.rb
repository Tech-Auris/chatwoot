# One fixed rule that makes an AI teammate raise her hand. Subclasses say
# whose alert it is (`persona`), when it may run (`business_hours?` for the
# front desk; once a day at `daily_at` for the slow numbers) and return the
# numbers behind the alert from `payload`, or nil when all is fine. The
# limits can be changed per account in `settings['virtual_clinic_alerts']`.
class VirtualClinic::Alerts::Rule
  BUSINESS_DAYS = (1..6) # Monday to Saturday
  BUSINESS_HOURS = (8...19)
  COOLDOWN = 4.hours

  attr_reader :account

  def self.key
    name.demodulize.underscore
  end

  def initialize(account, now: Time.current)
    @account = account
    @now = now.in_time_zone(account.reporting_timezone.presence || 'America/Sao_Paulo')
  end

  def persona
    'secretary'
  end

  # Whether the rule should be checked now (the job runs every 15 minutes).
  def due?
    BUSINESS_DAYS.cover?(@now.wday) && BUSINESS_HOURS.cover?(@now.hour)
  end

  def payload
    raise NotImplementedError
  end

  private

  def setting(key, default)
    account.settings.dig('virtual_clinic_alerts', key.to_s).presence || default
  end

  def minutes_since(time)
    ((Time.current - time) / 60).floor
  end
end
