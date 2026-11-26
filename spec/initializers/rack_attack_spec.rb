require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
describe 'Rack::Attack throttles' do
  let(:ip) { '203.0.113.7' }

  def throttle_key(name, env)
    Rack::Attack.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
  end

  def build_env(path, body, content_type, method: 'POST')
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'SCRIPT_NAME' => '',
      'QUERY_STRING' => '',
      'CONTENT_TYPE' => content_type,
      'CONTENT_LENGTH' => body.bytesize.to_s,
      'REMOTE_ADDR' => ip,
      'rack.input' => StringIO.new(body),
      'rack.url_scheme' => 'http',
      'action_dispatch.remote_ip' => ip
    }
  end

  def json_env(body, path = '/auth/sign_in', method: 'POST')
    build_env(path, body.to_json, 'application/json', method: method)
  end

  def form_env(params, path = '/auth/sign_in')
    build_env(path, Rack::Utils.build_nested_query(params), 'application/x-www-form-urlencoded')
  end

  describe 'login/ip' do
    it 'counts form-encoded password sign-ins by ip' do
      expect(throttle_key('login/ip', form_env({ 'email' => 'a@b.com', 'password' => 'x' }))).to eq(ip)
    end

    it 'counts JSON password sign-ins by ip' do
      expect(throttle_key('login/ip', json_env({ email: 'a@b.com', password: 'x' }))).to eq(ip)
    end

    it 'counts a trailing-slash path in the same bucket' do
      expect(throttle_key('login/ip', json_env({ email: 'a@b.com', password: 'x' }, '/auth/sign_in/'))).to eq(ip)
    end

    it 'skips JSON verification submissions carrying mfa_token' do
      expect(throttle_key('login/ip', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to be_nil
    end
  end

  describe 'login/email' do
    it 'keys JSON password sign-ins by normalized email' do
      key = throttle_key('login/email', json_env({ email: ' User@Example.COM ', password: 'x' }))
      expect(key).to eq('user@example.com')
    end

    it 'keys sign-ins that pass the email via request header' do
      env = build_env('/auth/sign_in', '{"password":"x"}', 'application/json')
      env['HTTP_EMAIL'] = ' User@Example.COM '
      expect(throttle_key('login/email', env)).to eq('user@example.com')
    end

    it 'skips JSON verification submissions instead of sharing a blank key' do
      expect(throttle_key('login/email', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to be_nil
      expect(throttle_key('login/email', json_env({ otp_code: '123456' }))).to be_nil
    end

    it 'skips a non-string email instead of raising' do
      expect(throttle_key('login/email', json_env({ email: ['a@b.com'], password: 'x' }))).to be_nil
    end

    it 'skips malformed JSON bodies without raising' do
      env = build_env('/auth/sign_in', '{"email": broken', 'application/json')
      expect(throttle_key('login/email', env)).to be_nil
    end
  end

  describe 'mfa_login' do
    it 'counts JSON verification submissions by ip and keys them per mfa_token' do
      env = json_env({ mfa_token: 'tok', otp_code: '123456' })

      expect(throttle_key('mfa_login/ip', env)).to eq(ip)
      expect(throttle_key('mfa_login/token', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to eq('tok')
      expect(throttle_key('mfa_login/token', json_env({ mfa_token: 'other', otp_code: '123456' }))).to eq('other')
    end
  end

  describe 'reset_password/email' do
    it 'keys JSON requests by normalized email' do
      key = throttle_key('reset_password/email', json_env({ email: ' User@Example.COM ' }, '/auth/password'))
      expect(key).to eq('user@example.com')
    end

    it 'ignores the email header, which this endpoint does not honor' do
      env = build_env('/auth/password', '{}', 'application/json')
      env['HTTP_EMAIL'] = 'victim@example.com'
      expect(throttle_key('reset_password/email', env)).to be_nil
    end
  end

  describe 'resend_confirmation/email' do
    it 'skips requests without an email instead of sharing a blank key' do
      expect(throttle_key('resend_confirmation/email', json_env({}, '/resend_confirmation'))).to be_nil
    end
  end

  describe 'super_admin_login/email' do
    it 'keys form sign-ins by the normalized super admin email' do
      env = form_env({ 'super_admin' => { 'email' => ' Admin@Example.COM ', 'password' => 'x' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/email', env)).to eq('admin@example.com')
    end

    it 'gives each email its own bucket' do
      other = form_env({ 'super_admin' => { 'email' => 'other@example.com', 'password' => 'x' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/email', other)).to eq('other@example.com')
    end

    it 'skips a missing or non-hash super_admin param' do
      expect(throttle_key('super_admin_login/email', form_env({ 'email' => 'a@b.com' }, '/super_admin/sign_in'))).to be_nil
      expect(throttle_key('super_admin_login/email', form_env({ 'super_admin' => 'email' }, '/super_admin/sign_in'))).to be_nil
    end

    it 'skips malformed JSON bodies without raising' do
      env = build_env('/super_admin/sign_in', '{"super_admin": broken', 'application/json')
      expect(throttle_key('super_admin_login/email', env)).to be_nil
    end
  end

  describe 'widget throttles' do
    it 'counts contact updates on the singular route' do
      env = json_env({ name: 'x' }, '/api/v1/widget/contact', method: 'PATCH')
      expect(throttle_key('api/v1/widget/contact', env)).to eq(ip)
    end

    it 'counts transcript requests by ip' do
      env = json_env({ email: 'a@b.com' }, '/api/v1/widget/conversations/transcript')
      expect(throttle_key('api/v1/widget/conversations/transcript', env)).to eq(ip)
    end

    it 'keys conversation and message creates by ip and website token' do
      env = json_env({ website_token: 'wt' }, '/api/v1/widget/conversations')
      expect(throttle_key('api/v1/widget/conversations', env)).to eq("#{ip}:wt")
      expect(throttle_key('api/v1/widget/messages', json_env({ website_token: 'wt' }, '/api/v1/widget/messages'))).to eq("#{ip}:wt")
    end
  end

  describe 'agent management' do
    it 'keys agent creates and bulk creates per account, per day' do
      throttle = Rack::Attack.throttles.fetch('/api/v1/accounts/:account_id/agents POST')

      expect(throttle.period).to eq(1.day)
      expect(throttle.limit).to eq(100)
      expect(throttle_key(throttle.name, json_env({}, '/api/v1/accounts/7/agents'))).to eq('7')
      expect(throttle_key(throttle.name, json_env({}, '/api/v1/accounts/7/agents/bulk_create'))).to eq('7')
      expect(throttle_key(throttle.name, json_env({}, '/api/v1/accounts/7/agents/3', method: 'PATCH'))).to be_nil
    end

    it 'keys agent deletes per account, per day' do
      throttle = Rack::Attack.throttles.fetch('/api/v1/accounts/:account_id/agents/:id DELETE')

      expect(throttle.limit).to eq(50)
      expect(throttle_key(throttle.name, json_env({}, '/api/v1/accounts/7/agents/3', method: 'DELETE'))).to eq('7')
    end
  end

  describe 'trusted IPs' do
    after { ApiRateLimits.reset! }

    it 'still safelists internal IPs' do
      with_modified_env RACK_ATTACK_ALLOWED_IPS: '100.62.125.0/24' do
        ApiRateLimits.reset!
        env = json_env({ email: 'a@b.com', password: 'x' })
        env['action_dispatch.remote_ip'] = '100.62.125.9'

        expect(Rack::Attack.configuration.safelisted?(Rack::Attack::Request.new(env))).to be(true)
        expect(Rack::Attack.configuration.safelisted?(Rack::Attack::Request.new(json_env({})))).to be(false)
      end
    end
  end

  describe 'throttle event logging' do
    it 'logs which rule matched' do
      env = form_env({ 'email' => 'a@b.com', 'password' => 'x' })
      env['rack.attack.matched'] = 'login/ip'

      expect(Rails.logger).to receive(:warn).with(a_string_including('matched_rule: "login/ip"'))
      ActiveSupport::Notifications.instrument('throttle.rack_attack', request: Rack::Attack::Request.new(env))
    end
  end
end
# rubocop:enable RSpec/DescribeClass
