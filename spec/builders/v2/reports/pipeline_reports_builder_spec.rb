require 'rails_helper'

RSpec.describe 'Clinic pipeline reports' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:acompanhamento) { pipeline.stages.find_by(name: 'Acompanhamento') }
  let(:retorno) { pipeline.stages.find_by(name: 'Retorno') }
  let(:won) { pipeline.stages.won.first }
  let(:lost) { pipeline.stages.lost.first }
  let(:loss_reason) { create(:loss_reason, name: 'Trocou de interesse') }
  let(:params) { { pipeline_id: pipeline.id, since: 1.day.ago.to_i.to_s, until: 1.day.from_now.to_i.to_s } }

  before do
    3.times do |index|
      entry = Pipelines::AddContactService.new(pipeline: pipeline, contact: create(:contact, account: account)).perform
      case index
      when 0 then Pipelines::MoveEntryService.new(entry: entry, stage: won).perform
      when 1 then Pipelines::MoveEntryService.new(entry: entry, stage: lost, loss_reason_id: loss_reason.id).perform
      end
    end
  end

  describe V2::Reports::PipelineSummaryBuilder do
    it 'counts entries, contacts on each stage and exits to Ganho / Perdido' do
      rows = described_class.new(account: account, params: params).build.index_by { |row| row[:name] }

      expect(rows['Acompanhamento']).to include(entered_count: 3, in_stage_count: 1, won_count: 1, lost_count: 1, closed: false)
      expect(rows['Ganho']).to include(entered_count: 1, in_stage_count: 1, closed: true)
      expect(rows.keys).to eq(%w[Acompanhamento Retorno Ganho Perdido])
    end
  end

  describe V2::Reports::PipelineConversionBuilder do
    subject(:report) { described_class.new(account: account, params: params).build }

    it 'reports the win and loss rates and the loss reasons' do
      expect(report[:kpis]).to include(total: 3, won_count: 1, lost_count: 1, won_rate: 33.33, lost_rate: 33.33)
      expect(report[:loss_reasons]).to eq([{ id: loss_reason.id, name: 'Trocou de interesse', count: 1, percentage: 100.0 }])
    end

    it 'draws the funnel from the first stage to Ganho' do
      expect(report[:stages].map { |row| [row[:name], row[:count]] }).to eq([['Acompanhamento', 3], ['Retorno', 0], ['Ganho', 1]])
      expect(report[:stages].first[:conversion_rate]).to eq(0.0)
    end

    it 'does not read a pipeline of another account' do
      other = create(:pipeline)

      expect { described_class.new(account: account, params: params.merge(pipeline_id: other.id)).build }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
