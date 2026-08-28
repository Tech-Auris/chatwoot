require 'rails_helper'

RSpec.describe 'Commercial Stripe webhook', type: :request do
  let(:quote) do
    create(:sales_quote, prospect_name: 'Clínica Cinco', prospect_email: 'contato@clinicacinco.com.br',
                         stripe_customer_id: 'cus_1', status: :signed)
  end

  def event(type: 'checkout.session.completed', mode: 'payment', quote_id: quote.id, session_id: 'cs_1')
    {
      'type' => type,
      'data' => { 'object' => { 'id' => session_id, 'mode' => mode, 'setup_intent' => 'seti_1',
                                'metadata' => { 'sales_quote_id' => quote_id.to_s } } }
    }
  end

  def post_event(payload)
    allow(Stripe::Webhook).to receive(:construct_event).and_return(payload)
    post '/webhooks/commercial/stripe', params: {}, headers: { 'Stripe-Signature' => 't=1,v1=x' }
  end

  before do
    InstallationConfig.where(name: 'STRIPE_WEBHOOK_SECRET').first_or_create!(value: 'whsec_test')
    GlobalConfig.clear_cache
  end

  describe 'a paid checkout' do
    # Without this, a customer who pays and closes the tab has the money taken
    # and nothing recorded on our side.
    it 'marks the sale as paid and creates the account' do
      post_event(event)

      expect(response).to have_http_status(:ok)
      expect(quote.reload).to have_attributes(status: 'converted')
      expect(quote.account).to be_present
    end

    # Stripe retries until it gets an answer, so the same payment arrives more
    # than once.
    it 'does not create a second account when the event repeats' do
      post_event(event)
      post_event(event)

      expect(Account.count).to eq(1)
    end
  end

  describe 'a saved card' do
    it 'records the card the token charges will use' do
      post_event(event(mode: 'setup'))

      expect(quote.reload.token_payment_method_id).to eq('seti_1')
    end
  end

  describe 'refusals' do
    # Acting on an unsigned payload would let anybody mark a sale as paid.
    it 'rejects a payload whose signature does not check out' do
      allow(Stripe::Webhook).to receive(:construct_event).and_raise(Stripe::SignatureVerificationError.new('bad', 'sig'))

      post '/webhooks/commercial/stripe', params: {}, headers: { 'Stripe-Signature' => 'forjada' }

      expect(response).to have_http_status(:bad_request)
      expect(quote.reload.status).to eq('signed')
    end

    it 'refuses everything while no signing secret is configured' do
      InstallationConfig.where(name: 'STRIPE_WEBHOOK_SECRET').first.update!(value: '')
      GlobalConfig.clear_cache

      post '/webhooks/commercial/stripe', params: {}, headers: { 'Stripe-Signature' => 't=1,v1=x' }

      expect(response).to have_http_status(:bad_request)
    end

    it 'ignores an event about a proposal it does not know' do
      post_event(event(quote_id: 999_999))

      expect(response).to have_http_status(:ok)
    end

    it 'ignores event types it does not handle' do
      post_event(event(type: 'invoice.paid'))

      expect(quote.reload.status).to eq('signed')
    end
  end
end
