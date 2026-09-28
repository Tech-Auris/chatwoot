require 'rails_helper'

RSpec.describe V2::Reports::FunnelConversionDrilldownBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:group_name) { "Agendamento_#{SecureRandom.hex(4)}" }
  let(:stages) do
    {
      lead: create(:funnel_stage, name: "lead_#{SecureRandom.hex(4)}", position: 0),
      scheduled: create(:funnel_stage, name: "scheduled_#{SecureRandom.hex(4)}", position: 1, chart_group: group_name),
      rescheduled: create(:funnel_stage, name: "rescheduled_#{SecureRandom.hex(4)}", position: 2, chart_group: group_name),
      lost: create(:funnel_stage, name: "lost_#{SecureRandom.hex(4)}", position: 100, closed: true)
    }
  end
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.zone.now.end_of_day.to_i.to_s } }

  def conversation
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def stage_change(conv, new_stage, created_at: 1.day.ago, previous_stage: nil, loss_reason: nil)
    create(:funnel_stage_change, account: account, conversation_id: conv.id, contact: contact, inbox: inbox,
                                 previous_stage: previous_stage, new_stage: new_stage, loss_reason: loss_reason, created_at: created_at)
  end

  def drilldown(extra)
    described_class.new(account: account, params: params.merge(extra)).build
  end

  before do
    stub_const('V2::Reports::FunnelConversionBuilder::DRILLABLE_STAGE_KEYS', [group_name])
    stages
  end

  describe 'a chart stage' do
    let!(:rescheduled_conv) { conversation }
    let!(:scheduled_conv) { conversation }

    before do
      stage_change(rescheduled_conv, stages[:lead].name, created_at: 3.days.ago)
      stage_change(rescheduled_conv, stages[:scheduled].name, created_at: 2.days.ago, previous_stage: stages[:lead].name)
      stage_change(rescheduled_conv, stages[:rescheduled].name, created_at: 1.day.ago, previous_stage: stages[:scheduled].name)
      stage_change(scheduled_conv, stages[:scheduled].name, created_at: 2.days.ago)
      stage_change(conversation, stages[:scheduled].name, created_at: 10.days.ago) # before the period
      deleted = conversation
      stage_change(deleted, stages[:scheduled].name)
      deleted.delete
    end

    it 'lists one row per conversation, newest entry first, matching the chart count' do
      result = drilldown(stage_key: group_name)
      chart = V2::Reports::FunnelConversionBuilder.new(account: account, params: params).build

      expect(result[:rows].pluck(:conversation_id)).to eq([rescheduled_conv.display_id, scheduled_conv.display_id])
      expect(result[:meta][:total_count]).to eq(chart[:stages].find { |row| row[:key] == group_name }[:count])
      expect(result[:rows].first).to include(stage: stages[:rescheduled].name, previous_stage: stages[:scheduled].name,
                                             contact_name: 'Maria', inbox_name: inbox.name)
    end

    it 'pages the rows' do
      stub_const('V2::Reports::FunnelConversionDrilldownBuilder::PER_PAGE', 1)

      result = drilldown(stage_key: group_name, page: '2')

      expect(result[:rows].pluck(:conversation_id)).to eq([scheduled_conv.display_id])
      expect(result[:meta]).to include(current_page: 2, total_count: 2)
    end

    it 'refuses a stage that is not drillable' do
      expect { drilldown(stage_key: stages[:lead].name) }.to raise_error(described_class::UnknownStage)
    end
  end

  describe 'the leads of an ad' do
    def ad_conversation(source_id)
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            additional_attributes: { 'campaign_referral' => { 'source_id' => source_id, 'title' => 'Promo' } })
    end

    let!(:qualified_lead) { ad_conversation('AD_1') }

    before do
      stage_change(qualified_lead, stages[:lead].name, created_at: 2.days.ago)
      stage_change(qualified_lead, stages[:scheduled].name, created_at: 1.day.ago)
      stage_change(ad_conversation('AD_1'), stages[:lead].name)
      stage_change(ad_conversation('AD_2'), stages[:lead].name)
      stage_change(conversation, stages[:lead].name)
    end

    it 'lists the same leads the ad grid counts, each on its latest stage' do
      result = drilldown(kind: 'ad', source_id: 'AD_1')
      grid = V2::Reports::FunnelConversionBuilder.new(account: account, params: params).build[:campaign_breakdown]

      expect(result[:meta][:total_count]).to eq(grid.find { |row| row[:source_id] == 'AD_1' }[:leads])
      expect(result[:rows].find { |row| row[:conversation_id] == qualified_lead.display_id }[:stage]).to eq(stages[:scheduled].name)
    end
  end

  describe 'the losses' do
    let(:price) { create(:loss_reason, name: "price_#{SecureRandom.hex(4)}") }
    let(:no_answer) { create(:loss_reason, name: "no_answer_#{SecureRandom.hex(4)}") }

    before do
      twice_lost = conversation
      stage_change(twice_lost, stages[:lost].name, loss_reason: price, created_at: 2.days.ago)
      stage_change(twice_lost, stages[:lost].name, loss_reason: no_answer, created_at: 1.day.ago)
      stage_change(conversation, stages[:lost].name, loss_reason: price)
    end

    it 'lists one row per conversation and reason, like the donut total' do
      result = drilldown(kind: 'loss')
      donut_total = V2::Reports::FunnelConversionBuilder.new(account: account, params: params).build[:loss_reasons].sum { |row| row[:count] }

      expect(result[:meta][:total_count]).to eq(donut_total)
      expect(result[:rows].pluck(:loss_reason)).to contain_exactly(price.name, price.name, no_answer.name)
    end

    it 'narrows to one reason' do
      result = drilldown(kind: 'loss', loss_reason_id: no_answer.id.to_s)

      expect(result[:rows].pluck(:loss_reason)).to eq([no_answer.name])
    end
  end
end
