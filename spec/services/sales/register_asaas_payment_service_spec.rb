require 'rails_helper'

RSpec.describe Sales::RegisterAsaasPaymentService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:quote) do
    create(:sales_quote, status: :signed, payment_method: :card, billing_cycle: :semiannual, total_amount: 570_060,
                         asaas_payment_link_id: 'iggk1oa9g9u3is4p',
                         asaas_payment_link_url: 'https://www.asaas.com/c/iggk1oa9g9u3is4p',
                         prospect_name: 'Leonardo Giacon', prospect_email: 'leo@example.com', company_name: 'Clínica Rhoncus')
  end

  before do
    allow(client).to receive_messages(create_customer: Struct.new(:id).new('cus_9'), create_invoice: Struct.new(:id).new('in_9'))
    allow(client).to receive(:update_customer)
    allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
    allow(client).to receive(:pay_invoice_out_of_band)
  end

  it 'settles the sale on stripe, pays the invoice out of band and creates the account' do
    result = described_class.new(quote: quote, client: client).perform

    expect(client).to have_received(:pay_invoice_out_of_band).with('in_9', paid_via: 'asaas')
    expect(result.quote).to have_attributes(status: 'converted', stripe_customer_id: 'cus_9', stripe_invoice_id: 'in_9')
    expect(result.account.name).to eq('Clínica Rhoncus')
    # The account inherits the customer so token billing and renewals have
    # something to charge against.
    expect(result.account.stripe_customer_id).to eq('cus_9')
  end

  it 'records the AsaaS link on the event so the audit trail keeps the source' do
    described_class.new(quote: quote, client: client).perform

    event = quote.events.find_by(event: 'asaas_payment_registered')
    expect(event.metadata['asaas_payment_link_id']).to eq('iggk1oa9g9u3is4p')
    expect(event.metadata['total']).to eq(570_060)
  end

  it 'refuses a proposal being paid by PIX' do
    quote.update!(payment_method: :pix)

    expect { described_class.new(quote: quote, client: client).perform }
      .to raise_error(described_class::InvalidTransition, /não é de pagamento por cartão/)
  end

  it 'refuses a proposal that never reached AsaaS' do
    quote.update!(asaas_payment_link_id: nil)

    expect { described_class.new(quote: quote, client: client).perform }
      .to raise_error(described_class::InvalidTransition, /não passou pelo fluxo AsaaS/)
  end

  # The button is on a list that somebody may have open in two tabs.
  it 'refuses a sale that already became an account' do
    described_class.new(quote: quote, client: client).perform

    expect { described_class.new(quote: quote.reload, client: client).perform }
      .to raise_error(described_class::InvalidTransition, /já foi paga/)
  end
end
