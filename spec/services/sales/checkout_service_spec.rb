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
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:create_tax_id)
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))

      expect(checkout.checkout_url).to eq('https://checkout.stripe.com/x')
    end
  end

  describe 'paying by card' do
    before do
      sign_terms
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:create_tax_id)
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

  describe 'what the payment page opens with' do
    before do
      sign_terms
      quote.update!(prospect_name: 'Maria Souza', prospect_phone: '+5561981402211', prospect_document: '123.456.789-00')
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:create_tax_id)
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))
    end

    # Everything the prospect already typed on our form goes onto the Stripe
    # customer, so the payment page does not ask for it a second time.
    it 'pushes the details onto the Stripe customer' do
      checkout

      expect(client).to have_received(:update_customer)
        .with('cus_1', hash_including(email: quote.prospect_email, phone: '+5561981402211'))
    end

    it 'attaches the CPF when there is no company document' do
      checkout

      expect(client).to have_received(:create_tax_id).with('cus_1', type: 'br_cpf', value: '123.456.789-00')
    end

    it 'prefers the CNPJ when the customer asked for an invoice against it' do
      quote.update!(company_document: '12.345.678/0001-90', billing_name: 'Clínica Cinco Ltda')

      checkout

      expect(client).to have_received(:create_tax_id).with('cus_1', type: 'br_cnpj', value: '12.345.678/0001-90')
    end

    it 'bills the company name when the invoice goes to a CNPJ' do
      quote.update!(billing_name: 'Clínica Cinco Ltda')

      checkout

      expect(client).to have_received(:update_customer).with('cus_1', hash_including(name: 'Clínica Cinco Ltda'))
    end

    # A retried checkout would otherwise hit Stripe's refusal of a repeated
    # document.
    it 'does not attach a document the customer already carries' do
      allow(client).to receive(:list_tax_ids)
        .and_return(Struct.new(:data).new([Struct.new(:value).new('12345678900')]))

      checkout

      expect(client).not_to have_received(:create_tax_id)
    end

    # A document Stripe refuses cannot stop a sale — the customer can still type
    # it on the payment page.
    it 'carries on when Stripe refuses the document' do
      allow(client).to receive(:create_tax_id).and_raise(Integrations::Stripe::Client::InvalidRequest, 'invalid tax id')

      expect { checkout }.not_to raise_error
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
