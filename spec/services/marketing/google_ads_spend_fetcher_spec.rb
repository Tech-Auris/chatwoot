require 'rails_helper'

RSpec.describe Marketing::GoogleAdsSpendFetcher do
  let(:account) { create(:account) }
  let!(:integration) do
    create(:marketing_integration, :google_ads, account: account, status: :active)
  end

  around do |example|
    ClimateControl.modify(
      GOOGLE_ADS_OAUTH_CLIENT_ID: 'auris_oauth_id',
      GOOGLE_ADS_OAUTH_CLIENT_SECRET: 'auris_oauth_secret'
    ) { example.run }
  end

  def stub_oauth_success(access_token: 'ya29.new_access_token')
    stub_request(:post, Marketing::GoogleAdsSpendFetcher::OAUTH_ENDPOINT)
      .to_return(status: 200, body: { access_token: access_token, expires_in: 3600 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_search_stream(rows, code: 200)
    body = code == 200 ? [{ 'results' => rows }].to_json : { error: 'boom' }.to_json
    stub_request(:post, %r{googleads\.googleapis\.com/v20/customers/1234567890/googleAds:searchStream})
      .to_return(status: code, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    let(:sample_row) do
      {
        'campaign' => { 'id' => '111', 'name' => 'Clínicas Bra' },
        'metrics' => { 'costMicros' => '15_075_000' }, # micros
        'segments' => { 'date' => '2026-09-15' },
        'customer' => { 'currencyCode' => 'BRL' }
      }
    end

    it 'refreshes the OAuth token then upserts one CampaignSpend per row' do
      stub_oauth_success
      stub_search_stream([sample_row])

      expect { described_class.new(account: account).perform }.to change(CampaignSpend, :count).by(1)

      row = CampaignSpend.last
      expect(row).to have_attributes(
        provider: 'google_ads',
        source_id: '111',
        source_type: 'google_ads_campaign',
        amount_cents: 1507, # 15_075_000 micros / 10_000 = 1507 cents
        currency: 'BRL'
      )
    end

    it 'is idempotent — a second run over the same day updates the same row' do
      stub_oauth_success
      stub_search_stream([sample_row])
      described_class.new(account: account).perform

      updated = sample_row.deep_dup
      updated['metrics']['costMicros'] = '20_000_000'
      stub_search_stream([updated])

      expect { described_class.new(account: account).perform }.not_to change(CampaignSpend, :count)
      expect(CampaignSpend.last.amount_cents).to eq(2000)
    end

    it 'fails soft when the account has no active Google integration' do
      integration.update!(status: :disabled)

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false)
      expect(CampaignSpend.count).to eq(0)
      expect(WebMock).not_to have_requested(:post, /googleads/)
    end

    it 'fails soft when the OAuth refresh itself fails' do
      stub_request(:post, /oauth2\.googleapis\.com/).to_return(status: 400, body: '{"error":"invalid_grant"}')

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false)
    end

    it 'fails soft on a Google Ads API HTTP error' do
      stub_oauth_success
      stub_search_stream([], code: 400)

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false)
      expect(CampaignSpend.count).to eq(0)
    end

    it 'forwards the login-customer-id header when set on the integration' do
      integration.update!(credentials: integration.credentials.merge('login_customer_id' => '5551234567'))
      stub_oauth_success
      stub_search_stream([sample_row])

      described_class.new(account: account).perform

      expect(WebMock).to have_requested(:post, /googleads/).with(
        headers: { 'Login-Customer-Id' => '5551234567' }
      )
    end
  end
end
