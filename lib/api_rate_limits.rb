require 'ipaddr'

# Super Admin → Settings → Limites da API, read by Rack::Attack on every
# request. The parsed values are kept per process for REFRESH_INTERVAL so a
# busy instance doesn't hit Redis on each request; a change saved in the
# console applies everywhere within that interval, without a restart.
class ApiRateLimits
  REFRESH_INTERVAL = 30.seconds
  ALWAYS_INTERNAL = %w[127.0.0.1 ::1].freeze
  LIMITS = {
    per_ip: ['API_RATE_LIMIT_PER_IP', 600],
    per_token: ['API_RATE_LIMIT_PER_TOKEN', 600],
    messages_per_inbox: ['API_RATE_LIMIT_MESSAGES_PER_INBOX', 60]
  }.freeze

  class << self
    # Internal servers (n8n, Baileys, the AI) skip every limit. The console
    # list adds to RACK_ATTACK_ALLOWED_IPS, it doesn't replace it.
    def internal_ip?(ip)
      address = IPAddr.new(ip.to_s).native
      settings[:internal_ips].any? { |range| range.family == address.family && range.include?(address) }
    rescue IPAddr::Error
      false
    end

    LIMITS.each_key do |name|
      define_method(name) { settings[name] }
    end

    # One entry per line (commas also work): IPv4, IPv6 or a CIDR range.
    def invalid_entries(text)
      entries(text).reject { |entry| parse_ip(entry) }
    end

    def reset!
      @settings = nil
    end

    private

    def settings
      return @settings if @settings && @loaded_at > REFRESH_INTERVAL.ago

      @loaded_at = Time.current
      @settings = load_settings
    end

    def load_settings
      ips = ALWAYS_INTERNAL + entries(ENV.fetch('RACK_ATTACK_ALLOWED_IPS', '')) + entries(GlobalConfig.get_value('API_INTERNAL_IPS'))
      limits = LIMITS.transform_values { |(key, default)| GlobalConfig.get_value(key).to_i.nonzero? || default }
      limits.merge(internal_ips: ips.filter_map { |entry| parse_ip(entry) }).freeze
    end

    def entries(text)
      text.to_s.split(/[\s,]+/).compact_blank
    end

    def parse_ip(entry)
      IPAddr.new(entry)
    rescue IPAddr::Error
      nil
    end
  end
end
