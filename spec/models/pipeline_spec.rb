require 'rails_helper'

RSpec.describe Pipeline do
  let(:account) { create(:account, locale: :pt_BR) }

  it 'comes with Ganho and Perdido after the clinic stages' do
    pipeline = create(:pipeline, account: account)

    expect(pipeline.stages.map { |stage| [stage.name, stage.kind] }).to eq(
      [%w[Acompanhamento open], %w[Retorno open], %w[Ganho won], %w[Perdido lost]]
    )
  end

  it 'does not rename Ganho or Perdido' do
    won = create(:pipeline, account: account).stages.won.first

    expect(won.update(name: 'Fechou')).to be false
  end

  it 'keeps one pass in progress per contact and pipeline' do
    entry = create(:pipeline_entry, pipeline: create(:pipeline, account: account))

    expect { create(:pipeline_entry, pipeline: entry.pipeline, contact: entry.contact) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'lets a contact enter again once the previous pass closed' do
    entry = create(:pipeline_entry, pipeline: create(:pipeline, account: account))
    entry.update!(closed_at: Time.current)

    expect(create(:pipeline_entry, pipeline: entry.pipeline, contact: entry.contact)).to be_persisted
  end
end
