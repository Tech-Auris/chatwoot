require 'rails_helper'

describe ApiRateLimits do
  before { described_class.reset! }
  after { described_class.reset! }

  def configure(name, value)
    InstallationConfig.where(name: name).first_or_create!(value: value, locked: false).update!(value: value)
  end

  describe '.internal_ip?' do
    it 'always trusts localhost' do
      expect(described_class.internal_ip?('127.0.0.1')).to be(true)
      expect(described_class.internal_ip?('::1')).to be(true)
    end

    it 'trusts the IPs and ranges listed in Super Admin' do
      configure('API_INTERNAL_IPS', "100.62.125.0/24\n2804:14c::/32, 18.231.10.4")

      expect(described_class.internal_ip?('100.62.125.77')).to be(true)
      expect(described_class.internal_ip?('2804:14c:1::9')).to be(true)
      expect(described_class.internal_ip?('18.231.10.4')).to be(true)
      expect(described_class.internal_ip?('::ffff:100.62.125.77')).to be(true)
      expect(described_class.internal_ip?('100.62.126.1')).to be(false)
    end

    it 'adds RACK_ATTACK_ALLOWED_IPS to the Super Admin list' do
      configure('API_INTERNAL_IPS', '10.0.0.1')

      with_modified_env RACK_ATTACK_ALLOWED_IPS: '192.168.0.10' do
        expect(described_class.internal_ip?('192.168.0.10')).to be(true)
        expect(described_class.internal_ip?('10.0.0.1')).to be(true)
      end
    end

    it 'skips invalid entries instead of failing' do
      configure('API_INTERNAL_IPS', "foo\n10.0.0.1")

      expect(described_class.internal_ip?('10.0.0.1')).to be(true)
      expect(described_class.internal_ip?('garbage')).to be(false)
    end
  end

  describe 'limits' do
    it 'reads the values saved in Super Admin' do
      configure('API_RATE_LIMIT_PER_IP', '900')
      configure('API_RATE_LIMIT_PER_TOKEN', '300')
      configure('API_RATE_LIMIT_MESSAGES_PER_INBOX', '20')

      expect([described_class.per_ip, described_class.per_token, described_class.messages_per_inbox]).to eq([900, 300, 20])
    end

    it 'falls back to the defaults when a value is blank' do
      configure('API_RATE_LIMIT_PER_TOKEN', '')

      expect(described_class.per_token).to eq(600)
    end
  end

  describe '.invalid_entries' do
    it 'lists what is not an IP or a CIDR range' do
      expect(described_class.invalid_entries("10.0.0.0/8\nfoo, 999.1.1.1 ::1")).to eq(%w[foo 999.1.1.1])
    end
  end
end
