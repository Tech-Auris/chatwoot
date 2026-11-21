require 'rails_helper'

RSpec.describe Pipelines::MoveEntryService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:entry) { create(:pipeline_entry, pipeline: pipeline) }
  let(:retorno) { pipeline.stages.find_by(name: 'Retorno') }
  let(:won) { pipeline.stages.won.first }
  let(:lost) { pipeline.stages.lost.first }
  let(:loss_reason) { create(:loss_reason) }

  it 'moves the entry and records the move' do
    described_class.new(entry: entry, stage: retorno, reason: 'voltou').perform

    expect(entry.reload.stage).to eq(retorno)
    expect(entry.events.last).to have_attributes(from_stage_id: pipeline.first_open_stage.id, to_stage_id: retorno.id, reason: 'voltou')
  end

  it 'closes the pass on Ganho' do
    described_class.new(entry: entry, stage: won).perform

    expect(entry.reload.closed_at).to be_present
  end

  it 'asks for the loss reason on Perdido' do
    expect { described_class.new(entry: entry, stage: lost).perform }
      .to raise_error(CustomExceptions::Pipeline)

    described_class.new(entry: entry, stage: lost, loss_reason_id: loss_reason.id).perform
    expect(entry.reload).to have_attributes(loss_reason: loss_reason, closed_at: be_present)
  end

  it 'brings an entry back from Perdido' do
    described_class.new(entry: entry, stage: lost, loss_reason_id: loss_reason.id).perform
    described_class.new(entry: entry, stage: retorno).perform

    expect(entry.reload).to have_attributes(closed_at: nil, loss_reason: nil, stage: retorno)
  end

  it 'does not reopen a pass when the contact already entered again' do
    described_class.new(entry: entry, stage: won).perform
    create(:pipeline_entry, pipeline: pipeline, contact: entry.contact)

    expect { described_class.new(entry: entry, stage: retorno).perform }
      .to raise_error(CustomExceptions::Pipeline)
  end

  it 'refuses a stage of another pipeline' do
    other_stage = create(:pipeline, account: account).first_open_stage

    expect { described_class.new(entry: entry, stage: other_stage).perform }
      .to raise_error(CustomExceptions::Pipeline)
  end
end
