require 'rails_helper'

RSpec.describe Sales::CheckoutService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:quote) do
    create(:sales_quote, prospect_name: 'Clínica Cinco', prospect_email: 'contato@clinica.com',
                         total_amount: 89_700, billing_cycle: :annual, discount_summary: '10% reunião')
  end
  let(:urls) { { success: 'https://chat.auris.ia.br/obrigado', cancel: 'https://chat.auris.ia.br/pagamento' } }

  def checkout(method: 'card', quote_record: quote)
    described_class.new(quote: quote_record, payment_method: method, urls: urls, client: client).perform
  end

  # What the double was actually called with, so the payload can be read field
  # by field instead of matched blind.
  def received_session
    session_args = nil
    expect(client).to have_received(:create_checkout_session) { |args| session_args = args }
    session_args
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
      # What a monthly proposal is made of: the subscription and a setup fee
      # that is charged once.
      create(:sales_quote_item, sales_quote: quote, name: 'Plataforma Auris',
                                unit_amount: 89_700, recurring_interval: 'month')
      create(:sales_quote_item, sales_quote: quote, name: 'Implantação', unit_amount: 300_000, recurring_interval: nil)
      quote.update!(billing_cycle: :monthly, subtotal_amount: 389_700, discount_amount: 0, total_amount: 389_700)
      sign_terms
      allow(client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(client).to receive(:update_customer)
      allow(client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(client).to receive(:create_tax_id)
      allow(client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))
    end

    # The subscription carries the plan; the setup fee rides on the first
    # invoice and never comes back.
    it 'subscribes the recurring lines and charges the one-off ones once' do
      checkout

      lines = received_session[:line_items]
      expect(lines.map { |line| line[:price_data][:product_data][:name] }).to contain_exactly('Plataforma Auris', 'Implantação')
      expect(lines.find { |line| line[:price_data][:product_data][:name] == 'Plataforma Auris' }[:price_data][:recurring])
        .to eq({ interval: 'month' })
      expect(lines.find { |line| line[:price_data][:product_data][:name] == 'Implantação' }[:price_data]).not_to have_key(:recurring)
    end

    it 'opens a subscription rather than a single charge' do
      checkout

      expect(received_session[:mode]).to eq('subscription')
    end

    # The subscription renews month to month until the customer cancels, so
    # nothing on it claims a term.
    it 'ties the subscription to the proposal it came from' do
      checkout

      expect(received_session.dig(:subscription_data, :metadata)).to eq({ sales_quote_id: quote.id })
    end

    # The discount was agreed on the proposal as a whole and holds for as long
    # as the plan runs, so every line carries its share of it.
    it 'spreads the discount across the lines, for good' do
      quote.update!(discount_amount: 38_970, total_amount: 350_730)

      checkout

      amounts = received_session[:line_items].to_h { |line| [line[:price_data][:product_data][:name], line[:price_data][:unit_amount]] }
      expect(amounts).to eq('Plataforma Auris' => 80_730, 'Implantação' => 270_000)
      expect(amounts.values.sum).to eq(350_730)
    end

    # Rounding a percentage over several lines leaves cents behind, and the
    # first invoice still has to add up to what the customer agreed to.
    it 'adds up to the agreed total to the cent' do
      quote.update!(discount_amount: 33_333, total_amount: 356_367)

      checkout

      expect(received_session[:line_items].sum { |line| line[:price_data][:unit_amount] }).to eq(356_367)
    end

    it 'says what comes every month after the first invoice' do
      quote.update!(discount_amount: 38_970, total_amount: 350_730)

      expect(described_class.monthly_charge_for(quote.reload)).to eq(80_730)
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
      quote.update!(prospect_name: 'Maria Souza', prospect_phone: '+5561981402211', prospect_document: '529.982.247-25')
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

      expect(client).to have_received(:create_tax_id).with('cus_1', type: 'br_cpf', value: '529.982.247-25')
    end

    it 'prefers the CNPJ when the customer asked for an invoice against it' do
      quote.update!(company_document: '11.222.333/0001-81', billing_name: 'Clínica Cinco Ltda')

      checkout

      expect(client).to have_received(:create_tax_id).with('cus_1', type: 'br_cnpj', value: '11.222.333/0001-81')
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
        .and_return(Struct.new(:data).new([Struct.new(:value).new('52998224725')]))

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

  # A long plan paid by card is charged in a locked instalment book through
  # AsaaS; Stripe carries the monthly subscription and nothing else.
  describe 'paying a long plan by card' do
    let(:asaas) { instance_double(Integrations::Asaas::Client) }

    before do
      sign_terms
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:find_customer).and_return(nil)
      allow(asaas).to receive(:create_customer).and_return({ 'id' => 'cus_1' })
      allow(asaas).to receive(:create_installment).and_return({ 'id' => 'inst_1' })
      allow(asaas).to receive(:list_installment_payments)
        .and_return([{ 'id' => 'pay_1', 'dueDate' => '2026-09-20', 'invoiceUrl' => 'https://www.asaas.com/i/1' }])
    end

    it 'sends the customer to the first invoice URL' do
      result = checkout

      expect(result.checkout_url).to eq('https://www.asaas.com/i/1')
      expect(quote.reload).to have_attributes(status: 'signed', payment_method: 'card',
                                              asaas_customer_id: 'cus_1',
                                              asaas_installment_id: 'inst_1',
                                              asaas_invoice_url: 'https://www.asaas.com/i/1')
    end

    it 'locks the number of parcels at what the plan covers' do
      checkout

      expect(asaas).to have_received(:create_installment)
        .with(hash_including(billing_type: 'CREDIT_CARD', total_value_cents: 89_700, installment_count: 12))
    end

    it 'never opens a Stripe checkout' do
      allow(client).to receive(:create_checkout_session)

      checkout

      expect(client).not_to have_received(:create_checkout_session)
    end

    it 'records the instalment on the proposal history' do
      checkout

      expect(quote.events.pluck(:event)).to include('asaas_installment_created')
    end
  end

  # A long plan paid by boleto rides the same AsaaS instalment a card sale
  # rides — the only difference is the billing type, and boleto becomes a
  # book of N boletos, one per month.
  describe 'paying a long plan by boleto' do
    let(:asaas) { instance_double(Integrations::Asaas::Client) }

    before do
      # Boleto is off by default now — the seller has to flip it on from
      # the Reservations grid before the customer can pick it. The tests
      # in this block simulate a proposal where that already happened.
      quote.update!(boleto_enabled_at: 2.minutes.ago)
      sign_terms
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:find_customer).and_return(nil)
      allow(asaas).to receive(:create_customer).and_return({ 'id' => 'cus_1' })
      allow(asaas).to receive(:create_installment).and_return({ 'id' => 'inst_boleto' })
      allow(asaas).to receive(:list_installment_payments)
        .and_return([{ 'id' => 'pay_b1', 'dueDate' => '2026-09-20',
                       'invoiceUrl' => 'https://www.asaas.com/i/boleto_1' }])
    end

    it 'sends the customer to the first boleto invoice URL' do
      result = checkout(method: 'boleto')

      expect(result.checkout_url).to eq('https://www.asaas.com/i/boleto_1')
      expect(quote.reload).to have_attributes(status: 'signed', payment_method: 'boleto',
                                              asaas_installment_id: 'inst_boleto',
                                              asaas_invoice_url: 'https://www.asaas.com/i/boleto_1')
    end

    it 'asks AsaaS for a BOLETO instalment locked at the plan count' do
      checkout(method: 'boleto')

      expect(asaas).to have_received(:create_installment)
        .with(hash_including(billing_type: 'BOLETO', total_value_cents: 89_700, installment_count: 12))
    end

    it 'never touches Stripe' do
      allow(client).to receive(:create_checkout_session)

      checkout(method: 'boleto')

      expect(client).not_to have_received(:create_checkout_session)
    end

    it 'records the instalment on the proposal history with its billing type' do
      checkout(method: 'boleto')

      event = quote.events.find_by(event: 'asaas_installment_created')
      expect(event.metadata['billing_type']).to eq('BOLETO')
      expect(event.metadata['installment_count']).to eq(12)
    end

    it 'refuses boleto on the monthly plan' do
      quote.update!(billing_cycle: :monthly)

      expect { checkout(method: 'boleto') }.to raise_error(described_class::UnsupportedPaymentMethod, /mensal/)
    end

    # A customer who hits `payment_method=boleto` from a stale form or a
    # copy-pasted URL, before the seller has flipped the boleto flag on,
    # must be blocked here — the public page also hides the option, this
    # guard covers the case where the form was submitted from a state
    # that no longer reflects what the seller has released.
    it 'refuses boleto when the seller has not enabled it on the proposal' do
      quote.update!(boleto_enabled_at: nil)

      expect { checkout(method: 'boleto') }.to raise_error(described_class::UnsupportedPaymentMethod, /liberado/)
    end
  end

  # AsaaS customers are keyed by document, so a retried checkout must land on
  # the same customer id instead of spawning a new one for the same CPF.
  describe 'the AsaaS customer behind the sale' do
    let(:asaas) { instance_double(Integrations::Asaas::Client) }

    before do
      sign_terms
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:create_customer).and_return({ 'id' => 'cus_new' })
      allow(asaas).to receive(:create_installment).and_return({ 'id' => 'inst_1' })
      allow(asaas).to receive(:list_installment_payments)
        .and_return([{ 'id' => 'pay_1', 'dueDate' => '2026-09-20', 'invoiceUrl' => 'https://www.asaas.com/i/1' }])
    end

    it 'reuses the customer AsaaS already has for that document' do
      allow(asaas).to receive(:find_customer).and_return({ 'id' => 'cus_existing' })

      checkout

      expect(asaas).not_to have_received(:create_customer)
      expect(quote.reload.asaas_customer_id).to eq('cus_existing')
    end

    it 'creates one when the document is not on file' do
      allow(asaas).to receive(:find_customer).and_return(nil)
      quote.update!(prospect_document: '529.982.247-25')

      checkout

      expect(asaas).to have_received(:create_customer)
        .with(hash_including(cpf_cnpj: '529.982.247-25'))
      expect(quote.reload.asaas_customer_id).to eq('cus_new')
    end

    it 'keeps the customer id on the proposal so a retry does not spawn a second one' do
      allow(asaas).to receive(:find_customer).and_return(nil)
      quote.update!(asaas_customer_id: 'cus_saved')

      checkout

      expect(asaas).not_to have_received(:find_customer)
      expect(asaas).not_to have_received(:create_customer)
    end
  end

  # A customer who changes their mind leaves an open instalment behind, and a
  # payment on it would arrive against terms nobody is holding.
  describe 'when the payment method changes' do
    let(:asaas) { instance_double(Integrations::Asaas::Client) }

    before do
      sign_terms
      quote.update!(asaas_installment_id: 'inst_old', asaas_invoice_url: 'https://www.asaas.com/i/old')
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:delete_installment)
      allow(asaas).to receive(:find_customer).and_return({ 'id' => 'cus_existing' })
      allow(asaas).to receive(:create_installment).and_return({ 'id' => 'inst_new' })
      allow(asaas).to receive(:list_installment_payments)
        .and_return([{ 'id' => 'pay_1', 'dueDate' => '2026-09-20', 'invoiceUrl' => 'https://www.asaas.com/i/new' }])
    end

    it 'cancels the old instalment when the customer switches to pix' do
      checkout(method: 'pix')

      expect(asaas).to have_received(:delete_installment).with('inst_old')
      expect(quote.reload.asaas_installment_id).to be_nil
    end

    it 'leaves only the newest instalment standing when they pick the card again' do
      checkout

      expect(asaas).to have_received(:delete_installment).with('inst_old')
      expect(quote.reload.asaas_installment_id).to eq('inst_new')
    end

    # An instalment we cannot take down is a mess to sort out later, but
    # stopping the customer from paying is worse.
    it 'carries on when the old instalment cannot be removed' do
      allow(asaas).to receive(:delete_installment).and_raise(Integrations::Asaas::Client::ProviderUnavailable, 'timeout')

      expect { checkout(method: 'pix') }.not_to raise_error
    end
  end

  describe '.installments_for' do
    it 'locks a semiannual plan at six and an annual at twelve' do
      expect(described_class.installments_for(:semiannual)).to eq(6)
      expect(described_class.installments_for(:annual)).to eq(12)
    end

    it 'is one on a monthly plan or when no cycle was chosen' do
      expect(described_class.installments_for(:monthly)).to eq(1)
      expect(described_class.installments_for(nil)).to eq(1)
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

    it 'takes boleto on the longer plans and nowhere else' do
      expect(described_class.offers?('boleto', :semiannual)).to be(true)
      expect(described_class.offers?('boleto', :annual)).to be(true)
      expect(described_class.offers?('boleto', :monthly)).to be(false)
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
