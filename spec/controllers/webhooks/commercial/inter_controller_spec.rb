require 'rails_helper'

RSpec.describe 'Commercial Inter webhook', type: :request do
  let(:token) { 'inter_webhook_secret' }
  let(:stripe_client) { instance_double(Integrations::Stripe::Client) }
  let!(:quote) do
    create(:sales_quote, status: :signed, payment_method: :pix, billing_cycle: :annual,
                         total_amount: 1_076_400, prospect_name: 'Fábio Rocha',
                         prospect_email: 'fabio@clinica.com', company_name: 'Clínica Cinco',
                         inter_txid: 'auris_txid_1')
  end

  before do
    InstallationConfig.where(name: 'INTER_WEBHOOK_TOKEN').first_or_create!(value: token)
    GlobalConfig.clear_cache

    # RegisterPixPaymentService touches Stripe on the conversion path; stub
    # it away so the webhook tests do not depend on real Stripe fixtures.
    # Customer ids are unique per call because Account.stripe_customer_id
    # carries a unique index — a same-id return on two quotes would rollback
    # the second conversion.
    allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
    allow(stripe_client).to receive(:create_customer) do
      @stripe_customer_seq ||= 0
      Struct.new(:id).new("cus_#{@stripe_customer_seq += 1}")
    end
    allow(stripe_client).to receive_messages(create_invoice: Struct.new(:id).new('in_1'))
    allow(stripe_client).to receive(:update_customer)
    allow(stripe_client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
    allow(stripe_client).to receive(:pay_invoice_out_of_band)
    allow(Sales::ClickupCrmSyncJob).to receive(:perform_later)
  end

  def post_event(body:, path_token: token)
    post "/webhooks/commercial/inter/#{path_token}", params: body.to_json,
                                                     headers: { 'Content-Type' => 'application/json' }
  end

  # Every element under `pix` is one received PIX — Inter batches them so we
  # process each in turn.
  it 'converts a sale whose txid appears on the pix array' do
    post_event(body: {
                 'pix' => [{ 'endToEndId' => 'E12345',
                             'txid' => 'auris_txid_1', 'valor' => '1076.40',
                             'chave' => 'contato@auris.ia.br' }]
               })

    expect(response).to have_http_status(:ok)
    expect(quote.reload.status).to eq('converted')
    expect(quote.events.pluck(:event)).to include('inter_pix_received', 'pix_payment_registered')
  end

  it 'processes multiple pix events in a single payload' do
    other_quote = create(:sales_quote, status: :signed, payment_method: :pix, billing_cycle: :semiannual,
                                       total_amount: 538_200, prospect_name: 'Outro',
                                       prospect_email: 'o@x.com', company_name: 'Outra Clínica',
                                       inter_txid: 'auris_txid_2')

    post_event(body: {
                 'pix' => [
                   { 'txid' => 'auris_txid_1', 'valor' => '1076.40', 'endToEndId' => 'E1' },
                   { 'txid' => 'auris_txid_2', 'valor' => '538.20', 'endToEndId' => 'E2' }
                 ]
               })

    expect(quote.reload.status).to eq('converted')
    expect(other_quote.reload.status).to eq('converted')
  end

  it 'ignores a txid that matches no known cob' do
    post_event(body: { 'pix' => [{ 'txid' => 'unknown', 'valor' => '100.00' }] })

    expect(response).to have_http_status(:ok)
    expect(quote.reload.status).to eq('signed')
  end

  it 'refuses a request whose path token does not match' do
    post_event(body: { 'pix' => [] }, path_token: 'forjado')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses every payload while no token is configured' do
    InstallationConfig.where(name: 'INTER_WEBHOOK_TOKEN').first.update!(value: '')
    GlobalConfig.clear_cache

    post_event(body: { 'pix' => [] })

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers bad_request for an unparseable body' do
    post "/webhooks/commercial/inter/#{token}", params: 'not json',
                                                headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:bad_request)
  end

  # Inter retries an unacknowledged webhook, so a duplicate for a sale that
  # is already converted must still return 200.
  it 'answers ok when the sale is already converted' do
    quote.update!(status: :converted)

    post_event(body: { 'pix' => [{ 'txid' => 'auris_txid_1', 'valor' => '1076.40' }] })

    expect(response).to have_http_status(:ok)
  end
end
