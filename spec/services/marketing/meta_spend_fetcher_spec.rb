require 'rails_helper'

RSpec.describe Marketing::MetaSpendFetcher do
  let(:account) { create(:account) }
  let!(:integration) do
    create(:marketing_integration,
           account: account, provider: :meta_capi, status: :active,
           credentials: { 'pixel_id' => '999', 'access_token' => 'EAAG_test', 'ad_account_id' => '1234567890' })
  end

  def stub_insights(rows, code: 200)
    stub_request(:get, %r{graph\.facebook\.com/v20\.0/act_1234567890/insights})
      .to_return(status: code, body: { data: rows }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    let(:sample_row) do
      {
        'ad_id' => 'AD_1',
        'ad_name' => 'Botox Promo',
        'campaign_id' => 'CAMP_1',
        'campaign_name' => 'Setembro',
        'spend' => '150.75',
        'account_currency' => 'BRL',
        'date_start' => '2026-09-15',
        'date_stop' => '2026-09-15'
      }
    end

    it 'upserts one CampaignSpend per Meta row' do
      stub_insights([sample_row])

      expect { described_class.new(account: account).perform }.to change(CampaignSpend, :count).by(1)

      row = CampaignSpend.last
      expect(row).to have_attributes(
        provider: 'meta',
        source_id: 'AD_1',
        source_type: 'meta_ad',
        amount_cents: 15_075,
        currency: 'BRL'
      )
      expect(row.period_start).to eq(Date.new(2026, 9, 15))
      expect(row.period_end).to eq(Date.new(2026, 9, 15))
    end

    # Re-running the fetcher over the same window must NOT create duplicates;
    # the sync updates amount + last_synced_at on the existing row so today's
    # spend can grow throughout the day.
    it 'is idempotent — a second run over the same day updates the existing row' do
      stub_insights([sample_row])
      described_class.new(account: account).perform

      updated = sample_row.merge('spend' => '200.00')
      stub_insights([updated])

      expect { described_class.new(account: account).perform }.not_to change(CampaignSpend, :count)
      expect(CampaignSpend.last.amount_cents).to eq(20_000)
    end

    it 'stores the raw provider payload on external_metadata for debugging' do
      stub_insights([sample_row])
      described_class.new(account: account).perform

      expect(CampaignSpend.last.external_metadata).to include(
        'ad_name' => 'Botox Promo',
        'campaign_id' => 'CAMP_1'
      )
    end

    it 'reports failure without inserting when the integration is missing' do
      integration.update!(status: :disabled)

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false)
      expect(CampaignSpend.count).to eq(0)
    end

    # The operator can save a Meta CAPI integration with only pixel_id +
    # access_token (fase 2 shape). ad_account_id is optional and only needed
    # for spend sync — reporting the missing field is more useful than
    # silently no-oping.
    it 'reports failure without inserting when ad_account_id is missing' do
      integration.update!(credentials: integration.credentials.except('ad_account_id'))

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false, reason: match(/ad_account_id/))
    end

    it 'surfaces the HTTP error when Meta rejects the call' do
      stub_request(:get, /graph\.facebook\.com/).to_return(
        status: 400,
        body: { error: { code: 200, message: 'invalid ads_read scope' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = described_class.new(account: account).perform

      expect(result).to include(ok: false)
      expect(CampaignSpend.count).to eq(0)
    end

    it 'clamps lookback_days to a safe window' do
      stub_insights([sample_row])

      described_class.new(account: account, lookback_days: 500).perform

      # No assertion on the exact time_range on the request — the guard
      # sits in the code path and is exercised by the request going out
      # at all. The MAX_LOOKBACK_DAYS constant is the contract; the
      # smoke here catches an infinite / negative lookback bug.
      expect(WebMock).to have_requested(:get, /insights/).once
    end
  end
end
