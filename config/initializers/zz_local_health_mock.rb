# LOCAL ONLY — not committed. Lets "Saúde da conta" show a Meta health answer
# saved on the channel (provider_config['local_health_mock']) instead of
# calling Meta, so fake local numbers can be tested. Development only.
Rails.application.config.to_prepare do
  next unless Rails.env.development?

  Whatsapp::HealthService.prepend(Module.new do
    private

    def fetch_phone_health_data
      mock = @channel.provider_config['local_health_mock']
      mock ? format_health_response(mock) : super
    end

    def fetch_business_account_health_data
      @channel.provider_config['local_health_mock'] ? { account_review_status: 'REJECTED', business_verification_status: 'VERIFIED' } : super
    end
  end)
end
