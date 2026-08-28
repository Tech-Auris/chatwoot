require 'rails_helper'

RSpec.describe AutomationRules::ConditionsFilterService do
  let(:account) { create(:account, funnel_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:stage) { create(:funnel_stage, name: 'Agendado') }
  let!(:other_stage) { create(:funnel_stage, name: 'Perdido') }

  def rule_for(values, operator: 'equal_to')
    create(
      :automation_rule,
      account: account,
      event_name: 'conversation_updated',
      conditions: [
        { attribute_key: 'funnel_stage_id', filter_operator: operator, values: values, query_operator: nil }.with_indifferent_access
      ]
    )
  end

  # The condition is offered in the automation form; if the engine could not
  # evaluate it, every rule using it would silently never fire.
  it 'matches a conversation sitting in the chosen stage' do
    conversation = create(:conversation, account: account, inbox: inbox, funnel_stage: stage)

    expect(described_class.new(rule_for([stage.id]), conversation).perform).to be true
  end

  it 'does not match a conversation in another stage' do
    conversation = create(:conversation, account: account, inbox: inbox, funnel_stage: other_stage)

    expect(described_class.new(rule_for([stage.id]), conversation).perform).to be false
  end

  it 'matches everything except the chosen stage with not_equal_to' do
    conversation = create(:conversation, account: account, inbox: inbox, funnel_stage: other_stage)

    expect(described_class.new(rule_for([stage.id], operator: 'not_equal_to'), conversation).perform).to be true
  end

  it 'does not match a conversation that is in no stage at all' do
    conversation = create(:conversation, account: account, inbox: inbox, funnel_stage: nil)

    expect(described_class.new(rule_for([stage.id]), conversation).perform).to be false
  end
end
