require 'rails_helper'

RSpec.describe Sales::MetaPurchaseJob do
  let(:endpoint) { 'https://graph.facebook.com/v20.0/632639385938559/events' }
  let(:paid_at) { Time.zone.parse('2026-11-08 10:00:00') }
  let(:quote) do
    create(:sales_quote, prospect_name: 'Felicia Macedo Souza', prospect_email: ' Contato@ClinicaCinco.com.br ',
                         prospect_phone: '+55 61 98140-2211', billing_cycle: :annual, payment_method: :card,
                         subtotal_amount: 1_076_400, total_amount: 1_076_400, status: :paid,
                         fbclid: 'IwAR123', fbclid_captured_at: Time.zone.parse('2026-11-01 09:00:00'),
                         client_ip: '200.1.2.3', client_user_agent: 'Mozilla/5.0')
  end
  let(:sent) { {} }

  def sha(value)
    [Digest::SHA256.hexdigest(value)]
  end

  def config(name, value)
    InstallationConfig.where(name: name).first_or_create!(value: value)
  end

  before do
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Pro', unit_amount: 89_700, quantity: 12)
    config('COMMERCIAL_META_PIXEL_ID', '632639385938559')
    config('COMMERCIAL_META_CAPI_TOKEN', 'token-123')
    stub_request(:post, endpoint).to_return do |request|
      sent[:body] = JSON.parse(request.body)
      { status: 200, body: { events_received: 1 }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'sends a website Purchase with the contract total, the ad click and the hashed buyer' do
    described_class.perform_now(quote.id, paid_at.to_i)

    event = sent[:body]['data'].first
    expect(sent[:body]['access_token']).to eq('token-123')
    expect(event).to include('event_name' => 'Purchase', 'event_time' => paid_at.to_i,
                             'event_id' => "sales_quote_#{quote.id}_purchase", 'action_source' => 'website')
    expect(event['custom_data']).to include('value' => 10_764.0, 'currency' => 'BRL', 'content_name' => 'Plano Pro - annual')
    expect(event['user_data']).to include(
      'fbc' => "fb.1.#{Time.zone.parse('2026-11-01 09:00:00').to_i * 1000}.IwAR123",
      'em' => sha('contato@clinicacinco.com.br'), 'ph' => sha('5561981402211'),
      'fn' => sha('felicia'), 'ln' => sha('souza'),
      'client_ip_address' => '200.1.2.3', 'client_user_agent' => 'Mozilla/5.0'
    )
    expect(quote.events.where(event: 'meta_purchase_sent')).to exist
  end

  it 'goes as system_generated without fbc for a lead with no ad click paid by hand' do
    quote.update!(fbclid: nil, client_user_agent: nil, client_ip: nil)

    described_class.perform_now(quote.id, paid_at.to_i)

    event = sent[:body]['data'].first
    expect(event['action_source']).to eq('system_generated')
    expect(event['user_data']).not_to have_key('fbc')
  end

  it 'routes the event to Test Events while a test code is set' do
    config('COMMERCIAL_META_TEST_EVENT_CODE', 'TEST123')

    described_class.perform_now(quote.id, paid_at.to_i)

    expect(sent[:body]['test_event_code']).to eq('TEST123')
  end

  it 'sends nothing while no token is configured' do
    InstallationConfig.find_by(name: 'COMMERCIAL_META_CAPI_TOKEN').update!(value: '')

    described_class.perform_now(quote.id, paid_at.to_i)

    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it 'does not send the same sale twice' do
    2.times { described_class.perform_now(quote.id, paid_at.to_i) }

    expect(WebMock).to have_requested(:post, endpoint).once
  end

  it 'records the failure on the proposal once Meta keeps refusing' do
    stub_request(:post, endpoint).to_return(status: 400, body: { error: { message: 'Invalid OAuth' } }.to_json)

    perform_enqueued_jobs { described_class.perform_later(quote.id, paid_at.to_i) }

    expect(quote.events.where(event: 'meta_purchase_failed')).to exist
  end
end
