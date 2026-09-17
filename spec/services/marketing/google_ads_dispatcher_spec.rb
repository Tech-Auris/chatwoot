require 'rails_helper'

RSpec.describe Marketing::GoogleAdsDispatcher do
  let(:account) { create(:account) }
  let!(:integration) do
    create(:marketing_integration, :google_ads, account: account, status: :active)
  end
  let(:wa_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:wa_inbox) { create(:inbox, account: account, channel: wa_channel) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: wa_inbox) }
  let(:conversion_event) do
    create(:conversion_event, account: account, name: 'Ag', google_event_name: 'book_appointment',
                              trigger_type: :funnel_stage_reached, trigger_config: { 'funnel_stage_id' => 1 })
  end
  let(:dispatch) do
    create(:conversion_event_dispatch,
           account: account, conversion_event: conversion_event, conversation: conversation,
           provider: :google_ads_enhanced)
  end

  let(:captured) { { body: nil, headers: nil } }

  def stub_oauth_success(access_token: 'ya29.new_access_token')
    stub_request(:post, Marketing::GoogleAdsDispatcher::OAUTH_ENDPOINT)
      .to_return(status: 200, body: { access_token: access_token, expires_in: 3600 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_google_ads_success(body: { 'results' => [{ 'gclid' => 'CJ0KCQ-abc' }] })
    stub_request(:post, %r{googleads\.googleapis\.com/v20/customers/1234567890:uploadClickConversions}).with do |req|
      captured[:body] = req.body
      captured[:headers] = req.headers
      true
    end.to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # OAuth client_id/secret come from env and are Auris-wide.
  around do |example|
    ClimateControl.modify(
      GOOGLE_ADS_OAUTH_CLIENT_ID: 'auris_oauth_id',
      GOOGLE_ADS_OAUTH_CLIENT_SECRET: 'auris_oauth_secret'
    ) { example.run }
  end

  # gclid comes from the first incoming message's body — the site snippet
  # forwards it prefilled ("...gclid=CJ0KCQ-abc").
  def seed_gclid_in_conversation(gclid: 'CJ0KCQ-abc-123')
    create(:message, conversation: conversation, account: account, inbox: wa_inbox,
                     message_type: :incoming, content: "Bom dia, quero saber sobre a promoção gclid=#{gclid}")
  end

  describe '#perform' do
    it 'refreshes the OAuth token then POSTs the conversion and marks the dispatch sent' do
      seed_gclid_in_conversation
      stub_oauth_success
      stub_google_ads_success

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload).to have_attributes(status: 'sent', attempts: 1)
    end

    # No gclid on the conversation and no incoming message body with the
    # token = Google can't attribute it, no point sending.
    it 'marks permanently_failed when no gclid can be resolved' do
      stub_oauth_success

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
      expect(WebMock).not_to have_requested(:post, /googleads/)
    end

    it 'is a no-op when the dispatch is already sent' do
      dispatch.update!(status: :sent, attempts: 1)

      described_class.new(dispatch: dispatch).perform

      expect(WebMock).not_to have_requested(:post, /oauth2/)
      expect(WebMock).not_to have_requested(:post, /googleads/)
    end

    it 'marks permanently_failed when the account has no google_ads integration' do
      integration.update!(status: :disabled)
      seed_gclid_in_conversation

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
      expect(WebMock).not_to have_requested(:post, /googleads/)
    end
  end

  describe 'payload shape' do
    before do
      seed_gclid_in_conversation(gclid: 'CJ0KCQ-abc-999')
      stub_oauth_success
      stub_google_ads_success
      described_class.new(dispatch: dispatch).perform
    end

    let(:sent_body) { JSON.parse(captured[:body]) }
    let(:conversion) { sent_body['conversions'].first }

    it 'builds the conversionAction resource name from customer + conversion_action_id' do
      expect(conversion['conversionAction']).to eq('customers/1234567890/conversionActions/9876543210')
    end

    it 'forwards the resolved gclid' do
      expect(conversion['gclid']).to eq('CJ0KCQ-abc-999')
    end

    it 'includes conversionDateTime in the Google-expected timezone-aware format' do
      expect(conversion['conversionDateTime']).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/)
    end

    it 'sets partialFailure: true so Google returns per-row errors instead of failing the whole batch' do
      expect(sent_body['partialFailure']).to be(true)
    end

    it 'hashes phone digits-only via SHA256 and never sends the raw value' do
      expected = Digest::SHA256.hexdigest('5511999999999')
      expect(conversion['userIdentifiers']).to include('hashedPhoneNumber' => expected)
      expect(sent_body.to_s).not_to include('5511999999999')
    end
  end

  describe 'request headers' do
    before do
      seed_gclid_in_conversation
      stub_oauth_success(access_token: 'ya29.the-token')
      stub_google_ads_success
      described_class.new(dispatch: dispatch).perform
    end

    it 'authorizes with the refreshed access_token' do
      expect(captured[:headers]['Authorization']).to eq('Bearer ya29.the-token')
    end

    it 'sends the developer-token header from the integration credentials' do
      expect(captured[:headers]['Developer-Token']).to eq('DEV_TOKEN')
    end

    it 'omits login-customer-id when the credential is blank' do
      expect(captured[:headers]).not_to have_key('Login-Customer-Id')
    end
  end

  describe 'MCC-scoped integration' do
    before do
      integration.update!(credentials: integration.credentials.merge('login_customer_id' => '5551234567'))
      seed_gclid_in_conversation
      stub_oauth_success
      stub_google_ads_success
      described_class.new(dispatch: dispatch).perform
    end

    it 'forwards the login-customer-id header when set on the integration' do
      expect(captured[:headers]['Login-Customer-Id']).to eq('5551234567')
    end
  end

  describe 'error handling' do
    before { seed_gclid_in_conversation }

    it 'marks failed and re-raises on a 500 so Sidekiq retries' do
      stub_oauth_success
      stub_request(:post, /googleads.googleapis.com/).to_return(status: 500, body: '{"error":"boom"}',
                                                                headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(dispatch: dispatch).perform }.to raise_error(/transient error/)
      expect(dispatch.reload).to have_attributes(status: 'failed', attempts: 1)
    end

    # 401 = OAuth token was rejected (unlikely mid-flight since we just
    # refreshed, but possible if the refresh_token was revoked).
    it 'marks permanently_failed on a 401' do
      stub_oauth_success
      stub_request(:post, /googleads.googleapis.com/).to_return(status: 401, body: '{"error":"invalid_grant"}',
                                                                headers: { 'Content-Type' => 'application/json' })

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
    end

    it 'marks permanently_failed on a 404 (unknown conversion action)' do
      stub_oauth_success
      stub_request(:post, /googleads.googleapis.com/).to_return(status: 404, body: '{"error":"unknown"}',
                                                                headers: { 'Content-Type' => 'application/json' })

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
    end

    # Google returns 200 + partialFailureError when the row is rejected
    # (invalid hashed value, out-of-window date, etc). Treat as permanent.
    it 'marks permanently_failed on a 200 with partialFailureError present' do
      stub_oauth_success
      stub_request(:post, /googleads.googleapis.com/).to_return(status: 200,
                                                                body: { 'partialFailureError' => { 'code' => 3,
                                                                                                   'message' => 'invalid gclid' } }.to_json,
                                                                headers: { 'Content-Type' => 'application/json' })

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
    end

    it 'raises when the OAuth refresh itself fails' do
      stub_request(:post, /oauth2.googleapis.com/).to_return(status: 400, body: '{"error":"invalid_grant"}',
                                                             headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(dispatch: dispatch).perform }.to raise_error(/OAuth refresh failed/)
    end
  end
end
