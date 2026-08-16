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
end
