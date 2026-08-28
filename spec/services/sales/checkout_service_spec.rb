require 'rails_helper'

RSpec.describe Sales::CheckoutService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:quote) do
    create(:sales_quote, prospect_name: 'Clínica Cinco', prospect_email: 'contato@clinica.com',
                         total_amount: 89_700, billing_cycle: :annual, discount_summary: '10% venda')
  end
  let(:urls) { { success: 'https://chat.auris.ia.br/obrigado', cancel: 'https://chat.auris.ia.br/pagamento' } }

  def checkout(method: 'card', quote_record: quote)
    described_class.new(quote: quote_record, payment_method: method, urls: urls, client: client).perform
  end

  def sign_terms(quote_record = quote)
    acceptance = quote_record.terms_acceptances.create!(terms_version: create(:terms_version), status: :pending)
    acceptance.sign!(signer: { name: 'Maria', email: 'maria@clinica.com' }, ip_address: '1.1.1.1', user_agent: 'x')
  end

  describe 'the terms gate' do
    # Money must never move against a signature that was never recorded.
    it 'refuses to start a payment before the terms are signed' do
      expect { checkout }.to raise_error(described_class::TermsNotAccepted, /termos de uso/)
    end

    it 'proceeds once the signature exists' do
      sign_terms
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))

      expect(checkout.checkout_url).to eq('https://checkout.stripe.com/x')
    end
  end

  describe 'paying by card' do
    before do
      sign_terms
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))
    end

    # The proposal already carries the agreed total; sending catalogue prices
    # would quietly drop every discount.
    it 'charges the agreed total, not the catalogue price' do
      checkout

      expect(client).to have_received(:create_checkout_session)
        .with(hash_including(line_items: [hash_including(quantity: 1, price_data: hash_including(unit_amount: 89_700))]))
    end

    it 'offers up to twelve instalments on an annual plan' do
      checkout

      expect(client).to have_received(:create_checkout_session).with(hash_including(max_installments: 12))
    end

    it 'offers up to six on a semiannual plan' do
      quote.update!(billing_cycle: :semiannual)

      checkout

      expect(client).to have_received(:create_checkout_session).with(hash_including(max_installments: 6))
    end

    it 'offers none on a monthly plan' do
      quote.update!(billing_cycle: :monthly)

      checkout

      expect(client).to have_received(:create_checkout_session).with(hash_including(max_installments: 1))
    end

    it 'keeps the Stripe customer on the proposal for the invoices that follow' do
      checkout

      expect(quote.reload.stripe_customer_id).to eq('cus_1')
    end

    it 'reuses a customer the proposal already has' do
      quote.update!(stripe_customer_id: 'cus_existing')

      checkout

      expect(client).not_to have_received(:create_customer)
    end
  end

  describe 'paying by pix' do
    before { sign_terms }

    # PIX is settled outside Stripe, so nothing is charged here — the sale waits
    # for somebody to confirm the money arrived.
    it 'records the signature and waits for a manual confirmation' do
      result = checkout(method: 'pix')

      expect(result.awaiting_manual_payment).to be true
      expect(quote.reload).to have_attributes(status: 'signed', payment_method: 'pix')
      expect(quote.events.pluck(:event)).to include('awaiting_pix_payment')
    end

    it 'never touches Stripe' do
      allow(client).to receive(:create_checkout_session)

      checkout(method: 'pix')

      expect(client).not_to have_received(:create_checkout_session)
    end
  end

  describe 'the pix discount' do
    it 'is 10% on the annual plan and 5% on the semiannual' do
      expect(described_class.pix_discount_for(:annual)).to eq(10)
      expect(described_class.pix_discount_for(:semiannual)).to eq(5)
    end

    it 'is nothing on the monthly plan or when no cycle was chosen' do
      expect(described_class.pix_discount_for(:monthly)).to eq(0)
      expect(described_class.pix_discount_for(nil)).to eq(0)
    end
  end
end
