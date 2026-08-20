require 'rails_helper'

RSpec.describe Integrations::Stripe::Client do
  before { GlobalConfig.clear_cache }

  # Stripe SDK objects respond to their fields dynamically, so a verifying
  # double has nothing to verify against — a plain struct stands in for the
  # only field these examples read back.
  def stripe_resource(id)
    Struct.new(:id).new(id)
  end

  describe '#configured?' do
    it 'is false when neither the installation config nor the env var is set' do
      with_modified_env STRIPE_SECRET_KEY: nil do
        expect(described_class.new.configured?).to be false
      end
    end

    it 'reads the key from the installation config' do
      InstallationConfig.create!(name: 'STRIPE_SECRET_KEY', value: 'sk_test_from_config')
      GlobalConfig.clear_cache

      expect(described_class.new.configured?).to be true
    end

    it 'falls back to the env var when the installation config is blank' do
      with_modified_env STRIPE_SECRET_KEY: 'sk_test_from_env' do
        expect(described_class.new.configured?).to be true
      end
    end
  end

  describe 'credential handling' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    # The Stripe SDK exposes a process-wide `Stripe.api_key`. Assigning it from
    # a request would leak the credential across threads, so every call must
    # carry the key in its own request options instead.
    it 'passes the key per request instead of assigning the global' do
      allow(Stripe::Account).to receive(:retrieve).and_return(stripe_resource('acct_1'))

      client.account

      # The id has to be an explicit nil: `Account.retrieve` validates a truthy
      # first argument as a string, so an empty hash raises before the call.
      expect(Stripe::Account).to have_received(:retrieve).with(nil, { api_key: 'sk_test_explicit' })
      expect(Stripe.api_key).not_to eq('sk_test_explicit')
    end

    it 'reaches the real SDK signature without raising an argument error' do
      stub_request(:get, 'https://api.stripe.com/v1/account')
        .to_return(status: 200, body: { id: 'acct_1', object: 'account' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.account.id).to eq('acct_1')
    end
  end

  describe '#key_mode' do
    # The Account resource has no `livemode` attribute (unlike Product and
    # friends), so the environment can only be read off the key.
    it 'reads test and live out of the key' do
      expect(described_class.new(api_key: 'sk_test_123').key_mode).to eq(:test)
      expect(described_class.new(api_key: 'sk_live_123').key_mode).to eq(:live)
      expect(described_class.new(api_key: 'rk_test_123').key_mode).to eq(:test)
    end

    it 'reports unknown instead of assuming live for an unrecognised key' do
      expect(described_class.new(api_key: 'whatever').key_mode).to eq(:unknown)
    end

    it 'raises Unauthorized before touching Stripe when no key is configured' do
      with_modified_env STRIPE_SECRET_KEY: nil do
        allow(Stripe::Account).to receive(:retrieve)

        expect { described_class.new.account }.to raise_error(described_class::Unauthorized)
        expect(Stripe::Account).not_to have_received(:retrieve)
      end
    end
  end

  describe 'error translation' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    it 'maps authentication failures to Unauthorized' do
      allow(Stripe::Product).to receive(:list).and_raise(Stripe::AuthenticationError.new('bad key'))

      expect { client.list_products }.to raise_error(described_class::Unauthorized, /bad key/)
    end

    it 'maps invalid requests to InvalidRequest' do
      allow(Stripe::Product).to receive(:create).and_raise(Stripe::InvalidRequestError.new('name required', 'name'))

      expect { client.create_product(name: '') }.to raise_error(described_class::InvalidRequest, /name required/)
    end

    it 'maps connection failures to ProviderUnavailable' do
      allow(Stripe::Product).to receive(:list).and_raise(Stripe::APIConnectionError.new('timeout'))

      expect { client.list_products }.to raise_error(described_class::ProviderUnavailable, /timeout/)
    end
  end

  describe '#archive_product' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    # Stripe refuses to delete a product that has prices, and a deleted product
    # would break the invoices referencing it, so archiving is the only sane
    # "delete" the screen can offer.
    it 'flips active to false instead of deleting' do
      allow(Stripe::Product).to receive(:update).and_return(stripe_resource('prod_1'))

      client.archive_product('prod_1')

      expect(Stripe::Product).to have_received(:update).with('prod_1', { active: false }, { api_key: 'sk_test_explicit' })
    end
  end

  describe '#create_price' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    it 'sends a recurring price when an interval is given' do
      allow(Stripe::Price).to receive(:create).and_return(stripe_resource('price_1'))

      client.create_price(product_id: 'prod_1', unit_amount: 19_990, currency: 'brl', recurring_interval: 'month')

      expect(Stripe::Price).to have_received(:create).with(
        { product: 'prod_1', unit_amount: 19_990, currency: 'brl', recurring: { interval: 'month' } },
        { api_key: 'sk_test_explicit' }
      )
    end

    it 'sends a one-off price when no interval is given' do
      allow(Stripe::Price).to receive(:create).and_return(stripe_resource('price_1'))

      client.create_price(product_id: 'prod_1', unit_amount: 5000, currency: 'brl')

      expect(Stripe::Price).to have_received(:create).with(
        { product: 'prod_1', unit_amount: 5000, currency: 'brl' },
        { api_key: 'sk_test_explicit' }
      )
    end
  end

  describe '#create_subscription' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    # Card charging would fail for every customer who pays by PIX outside
    # Stripe, which is part of the base — billing is by invoice, always.
    it 'bills by invoice instead of charging a card' do
      allow(Stripe::Subscription).to receive(:create).and_return(stripe_resource('sub_1'))

      client.create_subscription(customer_id: 'cus_1', price_id: 'price_1')

      expect(Stripe::Subscription).to have_received(:create).with(
        {
          customer: 'cus_1',
          items: [{ price: 'price_1', quantity: 1 }],
          collection_method: 'send_invoice',
          days_until_due: 7
        },
        { api_key: 'sk_test_explicit' }
      )
    end
  end

  describe '#create_invoice' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    before do
      allow(Stripe::Invoice).to receive(:create).and_return(stripe_resource('in_1'))
      allow(Stripe::InvoiceItem).to receive(:create).and_return(stripe_resource('ii_1'))
      allow(Stripe::Invoice).to receive(:finalize_invoice).and_return(stripe_resource('in_1'))
    end

    # An invoice item created loose sits as "pending" on the customer and is
    # swept into whatever invoice closes next — including the subscription's.
    it 'binds every item to the invoice it just created' do
      client.create_invoice(customer_id: 'cus_1', items: [{ price_id: 'price_1', quantity: 2 }])

      expect(Stripe::InvoiceItem).to have_received(:create).with(
        { customer: 'cus_1', invoice: 'in_1', price: 'price_1', quantity: 2 },
        { api_key: 'sk_test_explicit' }
      )
    end

    # Only a finalized invoice can be paid or written off; a draft is invisible
    # to the customer and to the write-off.
    it 'finalizes the invoice so it becomes collectible' do
      client.create_invoice(customer_id: 'cus_1', items: [{ price_id: 'price_1' }])

      expect(Stripe::Invoice).to have_received(:finalize_invoice).with('in_1', {}, { api_key: 'sk_test_explicit' })
    end

    it 'sends a free amount in cents with its description' do
      client.create_invoice(
        customer_id: 'cus_1',
        items: [{ description: 'Pacote de tokens', unit_amount: 15_000, quantity: 2 }]
      )

      expect(Stripe::InvoiceItem).to have_received(:create).with(
        { customer: 'cus_1', invoice: 'in_1', amount: 30_000, currency: 'brl', description: 'Pacote de tokens' },
        { api_key: 'sk_test_explicit' }
      )
    end

    it 'bills by invoice and does not let Stripe advance it on its own' do
      client.create_invoice(customer_id: 'cus_1', items: [{ price_id: 'price_1' }], days_until_due: 15)

      expect(Stripe::Invoice).to have_received(:create).with(
        { customer: 'cus_1', collection_method: 'send_invoice', days_until_due: 15, auto_advance: false },
        { api_key: 'sk_test_explicit' }
      )
    end

    it 'refuses an invoice with no items instead of issuing an empty one' do
      expect { client.create_invoice(customer_id: 'cus_1', items: []) }
        .to raise_error(described_class::InvalidRequest, /pelo menos um item/)
      expect(Stripe::Invoice).not_to have_received(:create)
    end
  end

  describe '#pay_invoice_out_of_band' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    # The payment is registered first and the origin stamped after: a stamp that
    # failed leaves an invoice paid without its source, which is fixable. The
    # reverse would leave an unpaid invoice carrying a source, reading as money
    # that never came in.
    it 'settles the invoice before stamping where the money came in' do
      calls = []
      allow(Stripe::Invoice).to receive(:pay) { calls << :pay }.and_return(stripe_resource('in_1'))
      allow(Stripe::Invoice).to receive(:update) { calls << :update }.and_return(stripe_resource('in_1'))

      client.pay_invoice_out_of_band('in_1', paid_via: 'asaas')

      expect(calls).to eq([:pay, :update])
      expect(Stripe::Invoice).to have_received(:pay).with('in_1', { paid_out_of_band: true }, { api_key: 'sk_test_explicit' })
      expect(Stripe::Invoice).to have_received(:update).with(
        'in_1', { metadata: { 'aurischat_paid_via' => 'asaas' } }, { api_key: 'sk_test_explicit' }
      )
    end

    # An unknown origin would be written to Stripe and silently pollute the
    # answer to "how much came in through each account".
    it 'refuses an origin outside the known ones' do
      allow(Stripe::Invoice).to receive(:pay)

      expect { client.pay_invoice_out_of_band('in_1', paid_via: 'picpay') }
        .to raise_error(described_class::InvalidRequest, /picpay/)
      expect(Stripe::Invoice).not_to have_received(:pay)
    end
  end

  describe '#list_invoices' do
    subject(:client) { described_class.new(api_key: 'sk_test_explicit') }

    it 'sends only the filters it was given' do
      allow(Stripe::Invoice).to receive(:list).and_return(stripe_resource('list'))

      client.list_invoices(status: 'open')

      expect(Stripe::Invoice).to have_received(:list).with(
        { status: 'open', limit: 25 }, { api_key: 'sk_test_explicit' }
      )
    end

    it 'pages with the cursor of the last row already shown' do
      allow(Stripe::Invoice).to receive(:list).and_return(stripe_resource('list'))

      client.list_invoices(starting_after: 'in_9')

      expect(Stripe::Invoice).to have_received(:list).with(
        { limit: 25, starting_after: 'in_9' }, { api_key: 'sk_test_explicit' }
      )
    end
  end
end
