require 'rails_helper'

RSpec.describe Webhooks::Asaas::PaymentEventHandler do
  let(:stripe_client) { instance_double(Integrations::Stripe::Client) }
  let!(:quote) do
    create(:sales_quote, status: :signed, payment_method: :boleto, billing_cycle: :semiannual,
                         total_amount: 538_200, prospect_name: 'Fábio Rocha',
                         prospect_email: 'fabio@clinica.com', company_name: 'Clínica Cinco',
                         asaas_customer_id: 'cus_1', asaas_installment_id: 'inst_carne_1')
  end

  def payment(overrides = {})
    {
      'id' => 'pay_boleto_1', 'customer' => 'cus_1', 'installment' => 'inst_carne_1',
      'installmentNumber' => 1, 'value' => 897.00, 'billingType' => 'BOLETO',
      'status' => 'RECEIVED', 'dueDate' => '2026-09-20', 'paymentDate' => '2026-09-20'
    }.merge(overrides)
  end

  before do
    # RegisterAsaasPaymentService reaches for Stripe on the conversion path
    # and enqueues the ClickUp sync; stub both so the webhook tests stay
    # fast and do not depend on real Stripe fixtures.
    allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
    allow(stripe_client).to receive_messages(create_customer: Struct.new(:id).new('cus_stripe'),
                                             create_invoice: Struct.new(:id).new('in_1'))
    allow(stripe_client).to receive(:update_customer)
    allow(stripe_client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
    allow(stripe_client).to receive(:pay_invoice_out_of_band)
    allow(Sales::ClickupCrmSyncJob).to receive(:perform_later)
  end

  describe 'received / confirmed events' do
    it 'records the parcel in the audit trail' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment).perform

      row = SalesAsaasInstallmentPayment.find_by!(asaas_payment_id: 'pay_boleto_1')
      expect(row).to have_attributes(sales_quote: quote, asaas_installment_id: 'inst_carne_1',
                                     installment_number: 1, amount_cents: 89_700,
                                     status: 'received')
    end

    # First money-in on a signed sale mirrors the manual button — the sale
    # is settled on Stripe, the account is created, and the CRM sync job
    # is enqueued.
    it 'converts the sale on the first received parcel' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment).perform

      expect(quote.reload.status).to eq('converted')
      expect(quote.account).to be_present
    end

    it 'does not double-convert when a second parcel lands' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment).perform
      accounts_before = Account.count

      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment(overrides: {}).merge('id' => 'pay_boleto_2', 'installmentNumber' => 2)).perform

      expect(Account.count).to eq(accounts_before)
      expect(SalesAsaasInstallmentPayment.where(sales_quote: quote).count).to eq(2)
    end

    # AsaaS retries an unacknowledged webhook until it gets a 200. Handling
    # the same payment id twice is a no-op on our side.
    it 'is idempotent for the same payment id' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment).perform
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment).perform

      expect(SalesAsaasInstallmentPayment.where(asaas_payment_id: 'pay_boleto_1').count).to eq(1)
    end

    it 'accepts PAYMENT_CONFIRMED the same way it accepts PAYMENT_RECEIVED' do
      described_class.new(event: 'PAYMENT_CONFIRMED', payment: payment).perform

      row = SalesAsaasInstallmentPayment.find_by!(asaas_payment_id: 'pay_boleto_1')
      expect(row.status).to eq('confirmed')
      expect(quote.reload.status).to eq('converted')
    end
  end

  describe 'overdue and refunded events' do
    # Boleto 3 of 6 goes past its due date — record it, but do not touch
    # the sale itself. Finance decides what to do with the customer.
    it 'records an overdue parcel without touching the sale status' do
      described_class.new(event: 'PAYMENT_OVERDUE', payment: payment.merge('id' => 'pay_boleto_3', 'installmentNumber' => 3)).perform

      row = SalesAsaasInstallmentPayment.find_by!(asaas_payment_id: 'pay_boleto_3')
      expect(row.status).to eq('overdue')
      expect(quote.reload.status).to eq('signed')
    end

    it 'records a refund and leaves the sale as it was' do
      described_class.new(event: 'PAYMENT_REFUNDED', payment: payment).perform

      row = SalesAsaasInstallmentPayment.find_by!(asaas_payment_id: 'pay_boleto_1')
      expect(row.status).to eq('refunded')
    end
  end

  describe 'events that do not apply' do
    it 'ignores an event type we do not act on' do
      described_class.new(event: 'PAYMENT_CREATED', payment: payment).perform

      expect(SalesAsaasInstallmentPayment.count).to eq(0)
    end

    it 'ignores a payment that carries no installment id' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment.merge('installment' => nil)).perform

      expect(SalesAsaasInstallmentPayment.count).to eq(0)
    end

    it 'ignores an installment id we do not know' do
      described_class.new(event: 'PAYMENT_RECEIVED', payment: payment.merge('installment' => 'inst_unknown')).perform

      expect(SalesAsaasInstallmentPayment.count).to eq(0)
    end
  end
end
