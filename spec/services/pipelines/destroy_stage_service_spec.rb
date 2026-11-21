require 'rails_helper'

RSpec.describe Pipelines::DestroyStageService do
  let(:pipeline) { create(:pipeline) }
  let(:acompanhamento) { pipeline.stages.find_by(name: 'Acompanhamento') }
  let(:retorno) { pipeline.stages.find_by(name: 'Retorno') }

  it 'moves the contacts of the stage to the chosen one' do
    entry = create(:pipeline_entry, pipeline: pipeline, stage: acompanhamento)

    described_class.new(stage: acompanhamento, move_to_stage: retorno).perform

    expect(entry.reload.stage).to eq(retorno)
    expect(entry.events.last.to_stage).to eq(retorno)
    expect(PipelineStage.exists?(acompanhamento.id)).to be false
  end

  it 'asks where the contacts go' do
    create(:pipeline_entry, pipeline: pipeline, stage: acompanhamento)

    expect { described_class.new(stage: acompanhamento).perform }.to raise_error(CustomExceptions::Pipeline)
  end

  it 'keeps Ganho, Perdido and the last clinic stage' do
    expect { described_class.new(stage: pipeline.stages.won.first).perform }.to raise_error(CustomExceptions::Pipeline)

    described_class.new(stage: acompanhamento).perform
    expect { described_class.new(stage: retorno).perform }.to raise_error(CustomExceptions::Pipeline)
  end
end
