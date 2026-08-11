require 'rails_helper'

RSpec.describe Whatsapp::HealthService do
  # Factory forces default provider_config with phone_number_id='123456789'
  # and business_account_id='123456789'. Rebind here so tests read stable
  # ids instead of hardcoding the same string twice.
  let(:phone_number_id) { '123456789' }
  let(:waba_id) { '123456789' }
  let(:channel) do
    create(:channel_whatsapp,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:service) { described_class.new(channel) }

  let(:phone_response_body) do
    {
      id: 'phone-123',
      display_phone_number: '+55 51 9273-3008',
      verified_name: 'Leger POA',
      name_status: 'APPROVED',
      quality_rating: 'GREEN',
      messaging_limit_tier: 'TIER_UNKNOWN',
      account_mode: 'LIVE',
      code_verification_status: 'VERIFIED',
      webhook_configuration: {}
    }.to_json
  end

  before do
    # Phone endpoint asks for the full field set below — WABA asks for a
    # different `fields` list, so query matchers separate the two even
    # though the factory reuses `123456789` as both ids.
    stub_request(:get, %r{graph.facebook.com/.+/#{phone_number_id}})
      .with(query: hash_including(fields: /quality_rating/))
      .to_return(status: 200, body: phone_response_body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch_health_status' do
    # Real support case: operator saw "Conta desabilitada" in the Meta
    # Business Manager but the AurisChat health page was silent. That
    # signal lives on the WABA (`account_review_status`), not the phone
    # number, so we now hit a second endpoint and merge the WABA fields
    # into the same response payload.
    it 'merges the WABA account_review_status + business_verification_status into the payload' do
      stub_request(:get, %r{graph.facebook.com/.+/#{waba_id}})
        .with(query: hash_including(fields: 'account_review_status,business_verification_status'))
        .to_return(
          status: 200,
          body: { account_review_status: 'FLAGGED', business_verification_status: 'verified' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.fetch_health_status

      expect(result[:display_phone_number]).to eq('+55 51 9273-3008')
      expect(result[:account_review_status]).to eq('FLAGGED')
      expect(result[:business_verification_status]).to eq('verified')
    end

    it 'still returns the phone health data when the WABA call fails' do
      stub_request(:get, %r{graph.facebook.com/.+/#{waba_id}})
        .with(query: hash_including(fields: 'account_review_status,business_verification_status'))
        .to_return(status: 400, body: { error: { message: 'missing scope' } }.to_json)

      result = service.fetch_health_status

      expect(result[:display_phone_number]).to eq('+55 51 9273-3008')
      expect(result).not_to have_key(:account_review_status)
    end

    it 'skips the WABA call when business_account_id is not configured' do
      channel.provider_config.delete('business_account_id')
      channel.save!

      result = service.fetch_health_status

      expect(result[:display_phone_number]).to eq('+55 51 9273-3008')
      expect(result).not_to have_key(:account_review_status)
      expect(WebMock).not_to have_requested(:get, %r{graph.facebook.com/.+/#{waba_id}})
        .with(query: hash_including(fields: 'account_review_status,business_verification_status'))
    end
  end
end
