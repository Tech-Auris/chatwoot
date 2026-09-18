require 'rails_helper'

RSpec.describe 'Commercial AsaaS webhook', type: :request do
  let(:token) { 'webhook_secret' }
  let(:quote) do
    create(:sales_quote, status: :signed, payment_method: :boleto, billing_cycle: :semiannual,
                         total_amount: 538_200, asaas_customer_id: 'cus_1',
                         asaas_installment_id: 'inst_carne_1')
  end
  let(:handler) { instance_double(Webhooks::Asaas::PaymentEventHandler) }

  before do
    InstallationConfig.where(name: 'ASAAS_WEBHOOK_TOKEN').first_or_create!(value: token)
    GlobalConfig.clear_cache

    allow(Webhooks::Asaas::PaymentEventHandler).to receive(:new).and_return(handler)
    allow(handler).to receive(:perform)
  end

  def post_event(body:, headers: { 'asaas-access-token' => token })
    post '/webhooks/commercial/asaas', params: body.to_json,
                                       headers: headers.merge('Content-Type' => 'application/json')
  end

  it 'hands a signed event off to the handler' do
    body = { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_1', 'installment' => 'inst_carne_1' } }

    post_event(body: body)

    expect(response).to have_http_status(:ok)
    expect(Webhooks::Asaas::PaymentEventHandler).to have_received(:new)
      .with(event: 'PAYMENT_RECEIVED', payment: hash_including('id' => 'pay_1'))
    expect(handler).to have_received(:perform)
  end

  # Anything without a matching token cannot mark a sale as paid.
  it 'refuses a payload without a matching token' do
    post_event(body: { 'event' => 'PAYMENT_RECEIVED', 'payment' => {} },
               headers: { 'asaas-access-token' => 'forjada' })

    expect(response).to have_http_status(:unauthorized)
    expect(handler).not_to have_received(:perform)
  end

  it 'refuses everything while no token is configured' do
    InstallationConfig.where(name: 'ASAAS_WEBHOOK_TOKEN').first.update!(value: '')
    GlobalConfig.clear_cache

    post_event(body: { 'event' => 'PAYMENT_RECEIVED', 'payment' => {} })

    expect(response).to have_http_status(:unauthorized)
  end

  # A malformed body cannot be handed to the handler — reject it so AsaaS
  # stops retrying.
  it 'answers bad_request for an unparseable body' do
    post '/webhooks/commercial/asaas', params: 'not json',
                                       headers: { 'asaas-access-token' => token, 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:bad_request)
  end
end
