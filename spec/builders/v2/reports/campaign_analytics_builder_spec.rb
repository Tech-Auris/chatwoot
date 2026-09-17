require 'rails_helper'

RSpec.describe V2::Reports::CampaignAnalyticsBuilder do
  let(:account) { create(:account, average_ticket: 500.00) }
  let(:params) do
    { since: 30.days.ago.to_time.to_i.to_s, until: Time.zone.now.end_of_day.to_time.to_i.to_s }
  end
  let(:builder) { described_class.new(account: account, params: params) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    # Stage rows drive the SQL builder for scheduling_stage_names_sql; they
    # aren't referenced by name in assertions, but the builder scopes on them.
    create(:funnel_stage, name: 'Em Qualificação', position: 0)
    create(:funnel_stage, name: 'Agendado', position: 10, chart_group: 'Agendamento')
    create(:funnel_stage, name: 'Comparecimento (ganho)', position: 20, closed: true)
  end

  def conversation_from_ad(ad_id, ad_title: 'Botox Promo')
    create(:conversation, account: account, inbox: inbox, additional_attributes: {
             'campaign_referral' => { 'source_id' => ad_id, 'title' => ad_title }
           })
  end

  def stage_change_for(conv, new_stage_name)
    create(:funnel_stage_change,
           account: account, conversation_id: conv.id, contact: conv.contact, inbox: inbox,
           previous_stage: nil, new_stage: new_stage_name, created_at: 1.day.ago)
  end

  describe '#build' do
    context 'when a Meta ad has conversations, funnel changes, and spend' do
      let!(:conv1) { conversation_from_ad('AD_A') }
      let!(:conv2) { conversation_from_ad('AD_A', ad_title: 'Botox Promo — variação B') }

      before do
        stage_change_for(conv1, 'Em Qualificação')
        stage_change_for(conv2, 'Em Qualificação')
        stage_change_for(conv1, 'Agendado')
        stage_change_for(conv1, 'Comparecimento (ganho)')
        create(:campaign_spend, account: account, provider: :meta, source_id: 'AD_A', source_type: 'meta_ad',
                                period_start: Date.current, period_end: Date.current, amount_cents: 30_000, currency: 'BRL')
      end

      it 'aggregates conversations, funnel stages, revenue, spend and derived metrics' do
        row = builder.build.first

        expect(row).to include(
          source_type: 'meta_ad',
          source_id: 'AD_A',
          conversations_count: 2,
          qualified_count: 2,
          scheduled_count: 1,
          attendance_count: 1,
          revenue_cents: 50_000, # 1 attendance × 500.00 average_ticket
          spend_cents: 30_000
        )
        expect(row[:cpl_cents]).to eq(15_000) # 30_000 / 2 qualified
        expect(row[:cpa_cents]).to eq(30_000) # 30_000 / 1 attendance
        expect(row[:roas]).to eq(1.67)        # 50_000 / 30_000
        expect(row[:name]).to eq('Botox Promo')
      end
    end

    # An ad with spend but zero conversations still needs to show up — the
    # operator wants to see "I spent money on this ad and got nothing".
    context 'when a Meta ad has spend but no attributed conversations' do
      before do
        create(:campaign_spend, account: account, provider: :meta, source_id: 'AD_B', source_type: 'meta_ad',
                                period_start: Date.current, period_end: Date.current, amount_cents: 15_000, currency: 'BRL')
      end

      it 'renders a row with zero conversation-side counts and no ROAS' do
        row = builder.build.find { |r| r[:source_id] == 'AD_B' }
        expect(row).to include(conversations_count: 0, qualified_count: 0, spend_cents: 15_000)
        expect(row[:cpl_cents]).to be_nil
        expect(row[:roas]).to be_nil
      end
    end

    # Symmetric: an ad with conversations but no spend still shows up so
    # the operator can spot organic-looking traffic Meta forgot to charge.
    context 'when a Meta ad has conversations but no spend' do
      let!(:conv) { conversation_from_ad('AD_C') }

      before { stage_change_for(conv, 'Em Qualificação') }

      it 'renders the row with spend_cents=0 and no CPL' do
        row = builder.build.find { |r| r[:source_id] == 'AD_C' }
        expect(row).to include(conversations_count: 1, qualified_count: 1, spend_cents: 0)
        expect(row[:cpl_cents]).to be_nil
      end
    end

    context 'when Google campaigns have spend' do
      before do
        create(:campaign_spend, :google, account: account, source_id: 'GAD_1',
                                         period_start: Date.current, period_end: Date.current,
                                         amount_cents: 22_000, currency: 'BRL',
                                         external_metadata: { 'campaign' => { 'name' => 'Google Setembro' } })
      end

      it 'renders a spend-only row per Google campaign (no conversation-side data)' do
        row = builder.build.find { |r| r[:source_type] == 'google_ads_campaign' }
        expect(row).to include(source_id: 'GAD_1', spend_cents: 22_000, name: 'Google Setembro',
                               conversations_count: 0, revenue_cents: 0, cpl_cents: nil)
      end
    end

    it 'sorts rows by spend descending so the biggest spenders show up first' do
      create(:campaign_spend, account: account, provider: :meta, source_id: 'AD_SMALL', source_type: 'meta_ad',
                              period_start: Date.current, period_end: Date.current, amount_cents: 5_000, currency: 'BRL')
      create(:campaign_spend, account: account, provider: :meta, source_id: 'AD_BIG', source_type: 'meta_ad',
                              period_start: Date.current, period_end: Date.current, amount_cents: 50_000, currency: 'BRL')

      ids = builder.build.map { |row| row[:source_id] }
      expect(ids.first).to eq('AD_BIG')
    end
  end
end
