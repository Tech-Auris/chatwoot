require 'rails_helper'

RSpec.describe 'Commercial Stripe webhook', type: :request do
  let(:quote) do
    create(:sales_quote, prospect_name: 'Clínica Cinco', prospect_email: 'contato@clinicacinco.com.br',
                         stripe_customer_id: 'cus_1', status: :signed)
  end

  # Build the payload as a real `Stripe::Event` (not a plain Hash) so the
  # spec exercises the runtime type the gem hands back. A Hash-shaped fake
  # supports `.dig` and hides bugs like the metadata lookup calling `.dig`
  # on a `Stripe::StripeObject` (which does NOT implement it) and blowing up
  # with 500 at the endpoint.
  def event(type: 'checkout.session.completed', mode: 'payment', quote_id: quote.id, session_id: 'cs_1')
    Stripe::Event.construct_from(
      type: type,
      data: { object: { id: session_id, object: 'checkout.session', mode: mode,
                        setup_intent: 'seti_1', metadata: { sales_quote_id: quote_id.to_s } } }
    )
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

    # The paid-side CRM write on the deal task rides Sidekiq so a slow CK
    # write does not slow the customer's confirmation page.
    it 'enqueues the ClickUp CRM sync for the paid-fields phase' do
      expect { post_event(event) }
        .to have_enqueued_job(Sales::ClickupCrmSyncJob).with(quote.id, 'paid_fields')
    end
  end

  describe 'the recurring card' do
    let(:account) { create(:account) }

    def invoice_event(type, subscription: 'sub_1')
      Stripe::Event.construct_from(
        type: type,
        data: { object: { id: 'in_1', object: 'invoice', created: 1_794_000_000,
                          parent: { subscription_details: { subscription: subscription } } } }
      )
    end

    before { quote.update!(payment_method: :card_recurring, billing_cycle: :annual) }

    it 'keeps the subscription and plans its renewal when the first charge is paid' do
      payload = event(mode: 'subscription')
      payload['data']['object']['subscription'] = 'sub_1'

      expect { post_event(payload) }.to have_enqueued_job(Sales::CardRecurringScheduleJob).with(quote.id)
      expect(quote.reload).to have_attributes(status: 'converted', stripe_subscription_id: 'sub_1')
    end

    context 'with the account already running' do
      before { quote.update!(stripe_subscription_id: 'sub_1', account: account, status: :converted) }

      it 'starts the overdue count when a monthly charge fails, once' do
        post_event(invoice_event('invoice.payment_failed'))
        travel(3.days) { post_event(invoice_event('invoice.payment_failed')) }

        expect(quote.reload.payment_overdue_since).to eq(Time.zone.at(1_794_000_000))
        expect(quote.events.where(event: 'payment_failed').count).to eq(1)
      end

      it 'stops the count and brings back an account suspended for it when the charge is paid' do
        quote.update!(payment_overdue_since: 31.days.ago)
        Sales::OverdueSuspensionJob.perform_now

        post_event(invoice_event('invoice.paid'))

        expect(quote.reload.payment_overdue_since).to be_nil
        expect(account.reload).to be_active
      end

      it 'keeps an account the team suspended for another reason' do
        quote.update!(payment_overdue_since: 2.days.ago)
        account.suspended!

        post_event(invoice_event('invoice.paid'))

        expect(account.reload).to be_suspended
      end

      it 'ignores invoices of other subscriptions' do
        post_event(invoice_event('invoice.payment_failed', subscription: 'sub_other'))

        expect(response).to have_http_status(:ok)
        expect(quote.reload.payment_overdue_since).to be_nil
      end
    end
  end

  describe 'a saved card' do
    it 'records the card the token charges will use' do
      post_event(event(mode: 'setup'))

      expect(quote.reload.token_payment_method_id).to eq('seti_1')
    end

    # The last step of the closing checklist — the token card is what turns
    # the deal into "negócio fechado" on the pipeline.
    it 'enqueues the ClickUp status flip once the card is on file' do
      expect { post_event(event(mode: 'setup')) }
        .to have_enqueued_job(Sales::ClickupCrmSyncJob).with(quote.id, 'closed')
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
