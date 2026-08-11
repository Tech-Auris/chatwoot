class Whatsapp::HealthService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def fetch_health_status
    validate_channel!
    phone_data = fetch_phone_health_data
    # WABA-level status (account_review_status, business_verification_status)
    # lives on the business account object, not the phone number. Meta shows
    # "Conta desabilitada" on their UI when the WABA has been flagged /
    # declined / disabled by policy review, and the operator has no way to
    # know from our health page today because we only queried the phone.
    # Failures on this extra call must not break the page — the phone data
    # is still useful even when Meta refuses to answer the business call
    # (e.g. missing business_management scope on the token).
    phone_data.merge(fetch_business_account_health_data)
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      query: {
        fields: health_fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise e
  end

  def fetch_business_account_health_data
    waba_id = @channel.provider_config['business_account_id']
    return {} if waba_id.blank?

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}",
      query: { fields: 'account_review_status,business_verification_status', access_token: @access_token }
    )
    return log_and_return_empty("WABA fetch failed: #{response.code} - #{response.body}") unless response.success?

    data = response.parsed_response
    {
      account_review_status: data['account_review_status'],
      business_verification_status: data['business_verification_status']
    }
  rescue StandardError => e
    log_and_return_empty("WABA fetch errored: #{e.message}")
  end

  def log_and_return_empty(message)
    Rails.logger.warn "[WHATSAPP HEALTH] #{message}"
    {}
  end

  def health_fields
    %w[
      id
      quality_rating
      messaging_limit_tier
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def handle_response(response)
    unless response.success?
      error_message = "WhatsApp API request failed: #{response.code} - #{response.body}"
      Rails.logger.error "[WHATSAPP HEALTH] #{error_message}"
      raise error_message
    end

    data = response.parsed_response
    format_health_response(data)
  end

  def format_health_response(response)
    {
      id: response['id'],
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      messaging_limit_tier: response['messaging_limit_tier'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  def build_expected_webhook_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    return nil if frontend_url.blank?

    "#{frontend_url}/webhooks/whatsapp/#{@channel.phone_number}"
  end
end
