# Dev-only stub for the WhatsApp Health page. When WHATSAPP_HEALTH_STUB=1
# is set, Whatsapp::HealthService#fetch_health_status returns a fixed
# fixture instead of hitting graph.facebook.com — useful to exercise the
# UI (including the WABA-level "Conta desabilitada" state) without valid
# Meta credentials on a local inbox.
#
# Never active in production. To try different states, edit the hash
# below or set WHATSAPP_HEALTH_STUB_STATE=flagged|approved|restricted|pending.
return unless Rails.env.development? && ENV['WHATSAPP_HEALTH_STUB'] == '1'

WABA_STUB_STATES = {
  'approved' => { account_review_status: 'APPROVED',   business_verification_status: 'verified' },
  'pending' => { account_review_status: 'PENDING',    business_verification_status: 'pending' },
  'restricted' => { account_review_status: 'RESTRICTED', business_verification_status: 'verified' },
  'disabled' => { account_review_status: 'DISABLED',   business_verification_status: 'verified' },
  'flagged' => { account_review_status: 'FLAGGED',    business_verification_status: 'verified' }
}.freeze

Rails.application.config.after_initialize do
  Whatsapp::HealthService.class_eval do
    define_method(:fetch_health_status) do
      state = ENV.fetch('WHATSAPP_HEALTH_STUB_STATE', 'flagged')
      {
        id: 'stub-phone-id',
        display_phone_number: @channel.phone_number,
        verified_name: 'Stubbed Business',
        name_status: 'APPROVED',
        quality_rating: 'GREEN',
        messaging_limit_tier: 'TIER_1K',
        account_mode: 'LIVE',
        code_verification_status: 'VERIFIED',
        webhook_configuration: { 'application' => 'stub' },
        expected_webhook_url: nil,
        throughput: { 'level' => 'STANDARD' },
        last_onboarded_time: nil,
        platform_type: 'CLOUD_API',
        certificate: nil,
        business_id: @channel.provider_config['business_account_id']
      }.merge(WABA_STUB_STATES.fetch(state, WABA_STUB_STATES['flagged']))
    end
  end
end
