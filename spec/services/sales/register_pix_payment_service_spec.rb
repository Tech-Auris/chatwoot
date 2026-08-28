require 'rails_helper'

RSpec.describe Sales::RegisterPixPaymentService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:terms_version) { create(:terms_version) }
  let(:quote) do
    create(:sales_quote, status: :signed, payment_method: :pix, billing_cycle: :semiannual, total_amount: 478_800,
                         prospect_name: 'Felicia Macedo', prospect_email: 'felicia@exemplo.com', company_name: 'Clínica Cinco')
  end

  before do
    allow(client).to receive_messages(create_customer: Struct.new(:id).new('cus_9'), create_invoice: Struct.new(:id).new('in_9'))
    allow(client).to receive(:update_customer)
    allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
    allow(client).to receive(:pay_invoice_out_of_band)
  end

  it 'settles the sale in stripe, creates the account and opens the next period' do
    result = described_class.new(quote: quote, paid_via: 'inter', client: client).perform

    expect(client).to have_received(:pay_invoice_out_of_band).with('in_9', paid_via: 'inter')
    # Payment and conversion happen in the same call, so the proposal lands on
    # its final state rather than pausing at `paid`.
    expect(result.quote).to have_attributes(status: 'converted', stripe_customer_id: 'cus_9', stripe_invoice_id: 'in_9')
    expect(result.account.name).to eq('Clínica Cinco')
    expect(result.renewal.due_on).to eq(Date.current + 6.months)
    expect(result.renewal.amount).to eq(478_800)
  end

  it 'records where the money came in' do
    described_class.new(quote: quote, paid_via: 'asaas', client: client).perform

    event = quote.events.find_by(event: 'pix_payment_registered')
    expect(event.metadata['paid_via']).to eq('asaas')
  end

  it 'refuses a proposal that is being paid by card' do
    quote.update!(payment_method: :card)

    expect { described_class.new(quote: quote, paid_via: 'inter', client: client).perform }
      .to raise_error(described_class::InvalidTransition, /não é de pagamento por PIX/)
  end

  # The button is on a list that somebody may have open in two tabs.
  it 'refuses a sale that already became an account' do
    described_class.new(quote: quote, paid_via: 'inter', client: client).perform

    expect { described_class.new(quote: quote.reload, paid_via: 'inter', client: client).perform }
      .to raise_error(described_class::InvalidTransition, /já foi paga/)
  end
end
