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
      quote.update!(billing_cycle: :monthly)
      sign_terms
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:create_tax_id)
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))

      expect(checkout.checkout_url).to eq('https://checkout.stripe.com/x')
    end
  end

  # The monthly plan is the one Stripe carries, because the recurrence lives
  # there.
  describe 'paying the monthly plan by card' do
    before do
      quote.update!(billing_cycle: :monthly)
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

    # A monthly subscription is charged month by month; there is nothing to
    # split.
    it 'offers no instalments' do
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
      quote.update!(billing_cycle: :monthly)
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

  # A long plan paid by card is charged in instalments through AsaaS; Stripe
  # carries the monthly subscription and nothing else.
  describe 'paying a long plan by card' do
    let(:asaas) { instance_double(Integrations::Asaas::Client) }

    before do
      sign_terms
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:create_payment_link)
        .and_return({ 'id' => 'pay_link_1', 'url' => 'https://www.asaas.com/c/pay_link_1' })
    end

    it 'sends the customer to an AsaaS payment link' do
      result = checkout

      expect(result.checkout_url).to eq('https://www.asaas.com/c/pay_link_1')
      expect(quote.reload).to have_attributes(status: 'signed', payment_method: 'card',
                                              asaas_payment_link_id: 'pay_link_1',
                                              asaas_payment_link_url: 'https://www.asaas.com/c/pay_link_1')
    end

    it 'charges the agreed total and offers the instalments of the plan' do
      checkout

      expect(asaas).to have_received(:create_payment_link)
        .with(hash_including(value_cents: 89_700, max_installment_count: 12))
    end

    it 'never opens a Stripe checkout' do
      allow(client).to receive(:create_checkout_session)

      checkout

      expect(client).not_to have_received(:create_checkout_session)
    end

    it 'records the link on the proposal history' do
      checkout

      expect(quote.events.pluck(:event)).to include('asaas_link_created')
    end
  end

  describe 'how many instalments are offered' do
    after { GlobalConfig.clear_cache }

    def configure(installments)
      InstallationConfig.where(name: 'ASAAS_MAX_INSTALLMENTS').first_or_create!(value: installments)
      GlobalConfig.clear_cache
    end

    it 'follows what Settings says' do
      configure('10')

      expect(described_class.max_installments_for(:annual)).to eq(10)
    end

    # Splitting a semiannual plan into ten would run past the period it pays for.
    it 'never runs past the months the plan covers' do
      configure('10')

      expect(described_class.max_installments_for(:semiannual)).to eq(6)
    end

    it 'has none to offer on a monthly plan' do
      configure('10')

      expect(described_class.max_installments_for(:monthly)).to eq(1)
    end
  end

  describe 'what each plan can be paid with' do
    # A monthly PIX would mean chasing a transfer every month; the monthly plan
    # is a subscription and lives on the card.
    it 'refuses pix on the monthly plan' do
      quote.update!(billing_cycle: :monthly)
      sign_terms

      expect { checkout(method: 'pix') }.to raise_error(described_class::UnsupportedPaymentMethod, /mensal/)
    end

    it 'takes pix on the longer plans' do
      expect(described_class.offers?('pix', :semiannual)).to be(true)
      expect(described_class.offers?('pix', :annual)).to be(true)
      expect(described_class.offers?('pix', :monthly)).to be(false)
    end

    it 'sends the card of a monthly plan to stripe and of a long plan to asaas' do
      expect(described_class.card_provider_for(:monthly)).to eq(:stripe)
      expect(described_class.card_provider_for(:semiannual)).to eq(:asaas)
      expect(described_class.card_provider_for(:annual)).to eq(:asaas)
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
