require 'rails_helper'

# Clinic pipelines in automations and filters: the "Etapa do funil"
# condition, the "Mover no funil para" action and the conversation filter,
# when the chosen funnel is a clinic pipeline.
RSpec.describe 'Clinic pipelines in automations and filters' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:acompanhamento) { pipeline.stages.find_by(name: 'Acompanhamento') }
  let(:retorno) { pipeline.stages.find_by(name: 'Retorno') }
  let(:lost) { pipeline.stages.lost.first }

  def rule_with_condition(stage, operator: 'equal_to')
    create(:automation_rule, account: account, event_name: 'conversation_updated',
                             conditions: [{ attribute_key: 'pipeline_stage_id', filter_operator: operator, values: [stage.id],
                                            query_operator: nil }.with_indifferent_access])
  end

  describe 'condition' do
    before { create(:pipeline_entry, pipeline: pipeline, contact: contact, stage: retorno) }

    it 'matches the conversations whose contact is on the stage' do
      expect(AutomationRules::ConditionsFilterService.new(rule_with_condition(retorno), conversation).perform).to be true
      expect(AutomationRules::ConditionsFilterService.new(rule_with_condition(acompanhamento), conversation).perform).to be false
    end

    it 'supports not_equal_to' do
      expect(AutomationRules::ConditionsFilterService.new(rule_with_condition(acompanhamento, operator: 'not_equal_to'), conversation).perform)
        .to be true
    end
  end

  describe 'action' do
    let(:rule) { create(:automation_rule, account: account) }
    let(:service) { AutomationRules::ActionService.new(rule, account, conversation) }

    it 'adds the contact to the pipeline as automatic, keeping the rule as the origin' do
      service.send(:move_to_pipeline_stage, [retorno.id])

      entry = pipeline.entries.sole
      expect(entry).to have_attributes(stage: retorno, source: 'automatic', origin: rule)
      expect(entry.events.last.source).to eq('automation')
    end

    it 'moves the pass in progress' do
      entry = create(:pipeline_entry, pipeline: pipeline, contact: contact)

      service.send(:move_to_pipeline_stage, [lost.id, create(:loss_reason).id])

      expect(entry.reload.stage).to eq(lost)
    end

    it 'does not bring back a lost contact who opted out of marketing' do
      create(:pipeline_entry, pipeline: pipeline, contact: contact, stage: lost, closed_at: 1.day.ago)
      contact.update!(marketing_opt_out: true)

      service.send(:move_to_pipeline_stage, [acompanhamento.id])

      expect(pipeline.entries.open_entries).to be_empty
    end

    it 'ignores a stage of another account' do
      service.send(:move_to_pipeline_stage, [create(:pipeline).first_open_stage.id])

      expect(PipelineEntry.where(contact: contact)).to be_empty
    end
  end

  describe 'rule validation' do
    it 'asks for the loss reason when moving to Perdido' do
      rule = build(:automation_rule, account: account, actions: [{ action_name: 'move_to_pipeline_stage', action_params: [lost.id] }])

      expect(rule).not_to be_valid
      rule.actions = [{ action_name: 'move_to_pipeline_stage', action_params: [lost.id, create(:loss_reason).id] }]
      expect(rule).to be_valid
    end
  end

  describe 'conversation filter' do
    it 'finds the conversations whose contact is on the stage' do
      create(:pipeline_entry, pipeline: pipeline, contact: contact, stage: retorno)
      conversation
      other = create(:conversation, account: account, inbox: inbox)
      admin = create(:user, account: account, role: :administrator)
      payload = [{ attribute_key: 'pipeline_stage_id', filter_operator: 'equal_to', values: [retorno.id], query_operator: nil }]

      result = Conversations::FilterService.new({ payload: payload }.with_indifferent_access, admin, account).perform

      expect(result[:conversations].map(&:id)).to include(conversation.id)
      expect(result[:conversations].map(&:id)).not_to include(other.id)
    end
  end

  describe 'deleting a stage used by an automation' do
    it 'is refused and names the automation' do
      create(:automation_rule, account: account, name: 'Retorno D+30',
                               actions: [{ action_name: 'move_to_pipeline_stage', action_params: [retorno.id] }])

      expect { Pipelines::DestroyStageService.new(stage: retorno).perform }
        .to raise_error(CustomExceptions::Pipeline, /Retorno D\+30/)
    end
  end

  describe 'webhook' do
    it 'sends pipeline_entry_updated to the account webhooks' do
      create(:webhook, account: account, inbox: nil, webhook_type: :account_type, subscriptions: ['pipeline_entry_updated'])
      allow(WebhookJob).to receive(:perform_later)
      entry = create(:pipeline_entry, pipeline: pipeline, contact: contact)
      event = Events::Base.new('pipeline_entry.updated', Time.zone.now, entry: entry, previous_stage: nil, new_stage: entry.stage)

      WebhookListener.instance.pipeline_entry_updated(event)

      expect(WebhookJob).to have_received(:perform_later)
        .with(anything, hash_including(event: 'pipeline_entry_updated', pipeline: { id: pipeline.id, name: pipeline.name }),
              :account_webhook, anything)
    end
  end
end
