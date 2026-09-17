require 'rails_helper'

RSpec.describe Marketing::SpendSyncJob do
  let(:meta_fetcher_instance) { instance_double(Marketing::MetaSpendFetcher, perform: { ok: true }) }
  let(:google_fetcher_instance) { instance_double(Marketing::GoogleAdsSpendFetcher, perform: { ok: true }) }

  before do
    allow(Marketing::MetaSpendFetcher).to receive(:new).and_return(meta_fetcher_instance)
    allow(Marketing::GoogleAdsSpendFetcher).to receive(:new).and_return(google_fetcher_instance)
  end

  describe '#perform' do
    let!(:account_with_meta) { create(:account).tap { |a| create(:marketing_integration, account: a, status: :active) } }
    let!(:account_with_disabled_integration) do
      create(:account).tap { |a| create(:marketing_integration, account: a, status: :disabled) }
    end
    let!(:account_with_google) do
      create(:account).tap { |a| create(:marketing_integration, :google_ads, account: a, status: :test_mode) }
    end
    let!(:account_with_both) do
      create(:account).tap do |a|
        create(:marketing_integration, account: a, status: :active)
        create(:marketing_integration, :google_ads, account: a, status: :active)
      end
    end
    before { create(:account) } # account without any marketing integration — must be skipped

    it 'runs the Meta fetcher only for accounts with an active/test_mode Meta integration' do
      described_class.new.perform

      expect(Marketing::MetaSpendFetcher).to have_received(:new).with(hash_including(account: account_with_meta, lookback_days: 7))
      expect(Marketing::MetaSpendFetcher).to have_received(:new).with(hash_including(account: account_with_both))
      expect(Marketing::MetaSpendFetcher).not_to have_received(:new).with(hash_including(account: account_with_google))
      expect(Marketing::MetaSpendFetcher).not_to have_received(:new).with(hash_including(account: account_with_disabled_integration))
    end

    it 'runs the Google fetcher only for accounts with an active/test_mode Google integration' do
      described_class.new.perform

      expect(Marketing::GoogleAdsSpendFetcher).to have_received(:new).with(hash_including(account: account_with_google))
      expect(Marketing::GoogleAdsSpendFetcher).to have_received(:new).with(hash_including(account: account_with_both))
      expect(Marketing::GoogleAdsSpendFetcher).not_to have_received(:new).with(hash_including(account: account_with_meta))
    end

    # A single provider blowing up must not abort the fan-out for other
    # accounts — the exception is captured and the loop keeps going.
    it 'captures fetcher exceptions and continues with the remaining accounts' do
      allow(Marketing::MetaSpendFetcher).to receive(:new).and_raise(StandardError.new('boom'))
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

      expect { described_class.new.perform }.not_to raise_error
      expect(Marketing::GoogleAdsSpendFetcher).to have_received(:new).at_least(:once)
    end
  end
end
