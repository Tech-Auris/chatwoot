require 'rails_helper'

RSpec.describe Pipelines::AddContactService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:user) { create(:user, account: account) }

  it 'puts the contact on the first stage and records the entry in the history' do
    entry = described_class.new(pipeline: pipeline, contact: contact, user: user).perform

    expect(entry.stage).to eq(pipeline.first_open_stage)
    expect(entry).to be_manual
    expect(entry.added_by).to eq(user)
    expect(entry.events.sole).to have_attributes(from_stage_id: nil, to_stage_id: entry.pipeline_stage_id, source: 'web')
  end

  it 'returns the entry in progress instead of adding the contact twice' do
    first = described_class.new(pipeline: pipeline, contact: contact).perform

    expect(described_class.new(pipeline: pipeline, contact: contact).perform).to eq(first)
    expect(pipeline.entries.count).to eq(1)
  end

  it 'keeps the automation that added the contact' do
    rule = create(:automation_rule, account: account)
    entry = described_class.new(pipeline: pipeline, contact: contact, source: :automatic, origin: rule).perform

    expect(entry).to have_attributes(source: 'automatic', origin: rule)
  end

  it 'refuses an archived pipeline' do
    pipeline.update!(archived_at: Time.current)

    expect { described_class.new(pipeline: pipeline, contact: contact).perform }
      .to raise_error(CustomExceptions::Pipeline)
  end
end
