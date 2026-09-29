require 'rails_helper'

RSpec.describe V2::Reports::CampaignAnalyticsDrilldownBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.zone.now.end_of_day.to_i.to_s, kind: 'ad', source_id: 'AD_1' } }
  let!(:qualifying) { FunnelStage.find_by(name: 'Em Qualificação') || create(:funnel_stage, name: 'Em Qualificação', position: 1) }

  def ad_conversation(source_id, created_at: 1.day.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: created_at,
                          additional_attributes: { 'campaign_referral' => { 'source_id' => source_id, 'title' => 'Botox' } })
  end

  def stage_change(conversation, stage, created_at: 1.day.ago)
    create(:funnel_stage_change, account: account, conversation_id: conversation.id, contact: contact, inbox: inbox,
                                 new_stage: stage, created_at: created_at)
  end

  def drill(metric)
    described_class.new(account: account, params: params.merge(metric: metric)).build
  end

  def report_row
    V2::Reports::CampaignAnalyticsBuilder.new(account: account, params: params).build.find { |row| row[:source_id] == 'AD_1' }
  end

  before do
    requalified = ad_conversation('AD_1')
    stage_change(requalified, qualifying.name, created_at: 2.days.ago)
    stage_change(requalified, qualifying.name)
    ad_conversation('AD_1')
    ad_conversation('AD_1', created_at: 10.days.ago) # created before the period
    stage_change(ad_conversation('AD_2'), qualifying.name)
  end

  it 'lists the conversations the Conversas column counts' do
    result = drill('conversations')

    expect(result[:meta][:total_count]).to eq(2)
    expect(result[:meta][:total_count]).to eq(report_row[:conversations_count])
  end

  it 'lists each qualified conversation once, matching the Qualificados column' do
    result = drill('qualified')

    expect(result[:meta][:total_count]).to eq(1)
    expect(result[:meta][:total_count]).to eq(report_row[:qualified_count])
    expect(result[:rows].first[:stage]).to eq(qualifying.name)
  end

  it 'refuses an unknown column' do
    expect { drill('revenue') }.to raise_error(described_class::UnknownStage)
  end
end
