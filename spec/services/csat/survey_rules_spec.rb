require 'rails_helper'

RSpec.describe Csat::SurveyRules do
  let(:account) { create(:account) }
  let(:lost) { create(:funnel_stage, name: 'Perdido', requires_loss_reason: true) }
  let(:scheduled) { create(:funnel_stage, name: 'Agendado') }
  let(:too_expensive) { create(:loss_reason, name: 'Achou caro') }
  let(:conversation) { create(:conversation, account: account) }

  def allowed?(conditions)
    described_class.new(conversation: conversation, survey_rules: { 'conditions' => conditions }).allowed?
  end

  def condition(key, operator, values, query_operator = nil)
    { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
  end

  it 'sends to everyone without conditions' do
    expect(allowed?([])).to be true
  end

  it 'follows the funnel stage and the loss reason together' do
    conversation.update!(funnel_stage: lost, loss_reason: too_expensive)

    expect(allowed?([condition('funnel_stage_id', 'equal_to', [lost.id], 'and'),
                     condition('loss_reason_id', 'equal_to', [too_expensive.id])])).to be true
    expect(allowed?([condition('funnel_stage_id', 'equal_to', [lost.id], 'and'),
                     condition('loss_reason_id', 'not_equal_to', [too_expensive.id])])).to be false
  end

  it 'sends when either side of an OU matches' do
    conversation.update!(funnel_stage: scheduled, label_list: ['vip'])

    expect(allowed?([condition('funnel_stage_id', 'equal_to', [lost.id], 'or'),
                     condition('labels', 'contains', ['vip'])])).to be true
    expect(allowed?([condition('funnel_stage_id', 'equal_to', [lost.id], 'and'),
                     condition('labels', 'contains', ['vip'])])).to be false
  end

  it 'keeps a rule saved before the conditions list working' do
    conversation.update!(label_list: ['bot-detectado'])

    rules = { 'operator' => 'does_not_contain', 'values' => ['bot-detectado'] }
    expect(described_class.new(conversation: conversation, survey_rules: rules).allowed?).to be false
  end
end
