require 'rails_helper'

RSpec.describe Marketing::MetaCapiDispatcher do
  let(:account) { create(:account) }
  let!(:integration) do
    create(:marketing_integration,
           account: account, provider: :meta_capi, status: :test_mode,
           credentials: { 'pixel_id' => '999888', 'access_token' => 'EAAG_test', 'test_event_code' => 'TEST123' })
  end
  let(:wa_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:wa_inbox) { create(:inbox, account: account, channel: wa_channel) }
  let(:contact) do
    create(:contact, account: account, phone_number: '+5511999999999').tap do |c|
      # Bypass the AR Contact email format validator to test the hasher's
      # normalization (Meta wants lower+trim on our side). Save via
      # update_column so the write skips validation.
      c.update_column(:email, 'Ana@Example.com') # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let(:conversation) do
    create(:conversation, account: account, contact: contact, inbox: wa_inbox,
                          additional_attributes: {
                            'campaign_referral' => { 'ctwa_clid' => 'CLID_ABC', 'title' => 'Ad' }
                          })
  end
  let(:conversion_event) do
    create(:conversion_event, account: account, name: 'Ag', meta_event_name: 'Schedule',
                              trigger_type: :funnel_stage_reached, trigger_config: { 'funnel_stage_id' => 1 })
  end
  let(:dispatch) do
    create(:conversion_event_dispatch,
           account: account, conversion_event: conversion_event, conversation: conversation,
           provider: :meta_capi)
  end

  # Meta returns { events_received: 1 } (or similar) on 2xx. WebMock stub
  # captures the request body into a shared hash so the shape assertions
  # can read it without re-hitting the request registry.
  let(:captured) { { body: nil } }

  def stub_meta_success(body: { 'events_received' => 1, 'fbtrace_id' => 'x' })
    stub_request(:post, %r{graph\.facebook\.com/v20\.0/999888/events}).with do |req|
      captured[:body] = req.body
      true
    end.to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'marks the dispatch sent on a 2xx response' do
      stub_meta_success

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload).to have_attributes(status: 'sent', attempts: 1)
      expect(dispatch.response).to include('events_received' => 1)
      expect(dispatch.last_attempted_at).to be_present
    end

    it 'is a no-op when the dispatch is already sent' do
      dispatch.update!(status: :sent, attempts: 1)

      described_class.new(dispatch: dispatch).perform

      expect(WebMock).not_to have_requested(:post, /graph\.facebook\.com/)
      expect(dispatch.reload.attempts).to eq(1)
    end

    # No active integration = configuration was never done or the operator
    # disabled it after the trigger fired. Not worth retrying.
    it 'marks permanently_failed when no active meta integration exists' do
      integration.update!(status: :disabled)

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
      expect(WebMock).not_to have_requested(:post, /graph\.facebook\.com/)
    end
  end

  describe 'payload shape' do
    let(:sent_body) { JSON.parse(captured[:body]) }

    before do
      stub_meta_success
      described_class.new(dispatch: dispatch).perform
    end

    it 'sends exactly one event with the CAPI click-to-messaging contract' do
      event = sent_body['data'].first
      expect(sent_body['data'].size).to eq(1)
      expect(event).to include(
        'event_name' => 'Schedule',
        'event_id' => dispatch.event_id,
        'action_source' => 'business_messaging',
        'messaging_channel' => 'whatsapp'
      )
      expect(event['event_time']).to eq(dispatch.created_at.to_i)
    end

    # Meta expects SHA256-hashed PII in user_data. The raw values never touch
    # the payload we persist or send.
    it 'hashes email and phone with SHA256 and drops the raw values' do
      event = sent_body['data'].first
      expected_email = Digest::SHA256.hexdigest('ana@example.com')
      expected_phone = Digest::SHA256.hexdigest('5511999999999')

      expect(event['user_data']).to include('em' => [expected_email], 'ph' => [expected_phone])
      expect(sent_body.to_s).not_to include('ana@example.com')
      expect(sent_body.to_s).not_to include('5511999999999')
    end

    it 'forwards the ctwa_clid captured on the conversation' do
      event = sent_body['data'].first
      expect(event['user_data']['ctwa_clid']).to eq('CLID_ABC')
    end

    it 'appends the integration test_event_code when status is test_mode' do
      expect(sent_body['test_event_code']).to eq('TEST123')
    end

    it 'includes the pixel access_token so Meta authenticates the call' do
      expect(sent_body['access_token']).to eq('EAAG_test')
    end
  end

  describe 'payload shape — non-WA channels' do
    let(:ig_inbox) { create(:inbox, account: account, channel: create(:channel_instagram, account: account)) }
    let(:ig_conv) do
      create(:conversation, account: account, contact: contact, inbox: ig_inbox,
                            additional_attributes: { 'campaign_referral' => { 'ctwa_clid' => 'IG_CLID' } })
    end
    let(:ig_dispatch) do
      create(:conversion_event_dispatch,
             account: account, conversion_event: conversion_event, conversation: ig_conv,
             provider: :meta_capi, event_id: 'cev-ig-1')
    end

    it 'maps Channel::Instagram to messaging_channel=instagram' do
      stub_meta_success
      described_class.new(dispatch: ig_dispatch).perform

      body = JSON.parse(captured[:body])
      expect(body['data'].first['messaging_channel']).to eq('instagram')
    end
  end

  describe 'active integration (not test_mode)' do
    before { integration.update!(status: :active) }

    it 'does not include test_event_code' do
      stub_meta_success
      described_class.new(dispatch: dispatch).perform

      body = JSON.parse(captured[:body])
      expect(body).not_to have_key('test_event_code')
    end
  end

  describe 'contact without PII' do
    before do
      contact.update!(email: nil, phone_number: nil)
      stub_meta_success
    end

    # Meta still accepts the event with only ctwa_clid in user_data; we let
    # them decide how to match.
    it 'sends the event with user_data containing only ctwa_clid' do
      described_class.new(dispatch: dispatch).perform

      user_data = JSON.parse(captured[:body])['data'].first['user_data']
      expect(user_data).to eq('ctwa_clid' => 'CLID_ABC')
    end
  end

  describe 'error handling' do
    # 5xx / network errors — Sidekiq retries, so we re-raise.
    it 'marks failed and re-raises on a 500 so Sidekiq retries' do
      stub_request(:post, /graph\.facebook\.com/).to_return(status: 500, body: '{"error":{"code":1,"message":"boom"}}',
                                                            headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(dispatch: dispatch).perform }.to raise_error(/transient error/)
      expect(dispatch.reload).to have_attributes(status: 'failed', attempts: 1)
    end

    # Invalid access token — no point retrying, mark permanent.
    it 'marks permanently_failed on Meta error code 190 (invalid access token)' do
      stub_request(:post, /graph\.facebook\.com/).to_return(status: 400,
                                                            body: '{"error":{"code":190,"message":"Invalid OAuth"}}',
                                                            headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(dispatch: dispatch).perform }.not_to raise_error
      expect(dispatch.reload.status).to eq('permanently_failed')
    end

    it 'marks permanently_failed on Meta error code 100 (invalid parameter / pixel)' do
      stub_request(:post, /graph\.facebook\.com/).to_return(status: 400,
                                                            body: '{"error":{"code":100,"message":"Invalid pixel"}}',
                                                            headers: { 'Content-Type' => 'application/json' })

      described_class.new(dispatch: dispatch).perform

      expect(dispatch.reload.status).to eq('permanently_failed')
    end
  end
end
