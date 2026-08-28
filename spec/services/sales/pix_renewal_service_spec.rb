require 'rails_helper'

RSpec.describe Sales::PixRenewalService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:account) { create(:account, stripe_customer_id: 'cus_1') }
  let(:quote) { create(:sales_quote, status: :converted, payment_method: :pix, billing_cycle: :monthly, total_amount: 89_700, account: account) }
  let(:renewal) { create(:pix_renewal, account: account, sales_quote: quote, due_on: 5.days.from_now.to_date, amount: 89_700) }

  def stripe_invoice(id: 'in_1')
    Struct.new(:id, :hosted_invoice_url).new(id, 'https://invoice.stripe.com/x')
  end

  describe '#issue_invoice!' do
    it 'bills the period and records where the invoice lives' do
      expect(client).to receive(:create_invoice).with(
        hash_including(customer_id: 'cus_1', days_until_due: 5, metadata: { pix_renewal_id: renewal.id })
      ).and_return(stripe_invoice)

      described_class.new(renewal: renewal, client: client).issue_invoice!

      expect(renewal.reload).to have_attributes(status: 'invoiced', stripe_invoice_id: 'in_1',
                                                hosted_invoice_url: 'https://invoice.stripe.com/x')
    end

    # Stripe counts the due date from today, so a period already past due still
    # needs a positive number of days.
    it 'bills an overdue period for tomorrow' do
      renewal.update!(due_on: 3.days.ago.to_date)
      expect(client).to receive(:create_invoice).with(hash_including(days_until_due: 1)).and_return(stripe_invoice)

      described_class.new(renewal: renewal, client: client).issue_invoice!
    end

    it 'refuses to bill the same period twice' do
      renewal.update!(status: :invoiced)

      expect { described_class.new(renewal: renewal, client: client).issue_invoice! }
        .to raise_error(described_class::InvalidTransition, /já foi faturada/)
    end

    it 'refuses an account without a stripe customer' do
      account.update!(stripe_customer_id: nil)

      expect { described_class.new(renewal: renewal, client: client).issue_invoice! }
        .to raise_error(described_class::InvalidTransition, /sem cliente do Stripe/)
    end
  end

  describe '#register_payment!' do
    before { renewal.update!(status: :invoiced, stripe_invoice_id: 'in_1') }

    it 'writes the invoice off and opens the next period' do
      expect(client).to receive(:pay_invoice_out_of_band).with('in_1', paid_via: 'inter')

      described_class.new(renewal: renewal, client: client).register_payment!(paid_via: 'inter')

      expect(renewal.reload).to have_attributes(status: 'paid', paid_via: 'inter')
      expect(renewal.paid_at).to be_present

      opened = PixRenewal.status_pending.last
      expect(opened.due_on).to eq(renewal.due_on + 1.month)
      expect(opened.amount).to eq(89_700)
    end

    it 'follows the cycle the plan was sold on' do
      quote.update!(billing_cycle: :annual)
      allow(client).to receive(:pay_invoice_out_of_band)

      described_class.new(renewal: renewal, client: client).register_payment!(paid_via: 'asaas')

      expect(PixRenewal.status_pending.last.due_on).to eq(renewal.due_on + 12.months)
    end

    it 'refuses a write-off before the invoice exists' do
      renewal.update!(status: :pending)

      expect { described_class.new(renewal: renewal, client: client).register_payment!(paid_via: 'inter') }
        .to raise_error(described_class::InvalidTransition, /Gere a fatura/)
    end
  end

  describe '#cancel!' do
    it 'stops the chain without opening another period' do
      described_class.new(renewal: renewal, client: client).cancel!

      expect(renewal.reload.status).to eq('cancelled')
      expect(PixRenewal.count).to eq(1)
    end

    it 'refuses to cancel a period already settled' do
      renewal.update!(status: :paid)

      expect { described_class.new(renewal: renewal, client: client).cancel! }
        .to raise_error(described_class::InvalidTransition, /paga/)
    end
  end
end
