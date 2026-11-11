require 'rails_helper'

RSpec.describe FollowUp do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'Conversation#follow_up_badge' do
    it 'is hidden once the patient came back' do
      create(:follow_up, conversation: conversation, outcome: :reengaged)

      expect(conversation.reload.follow_up_badge).to be_nil
    end

    it 'shows the sequence ended without an answer, then a new FUP running' do
      create(:follow_up, conversation: conversation, run_id: 'a', step: 3, outcome: :no_response, delivery_status: :sent)
      expect(conversation.reload.follow_up_badge).to include(step: 3, state: 'ended')

      create(:follow_up, conversation: conversation, run_id: 'b', step: 1, delivery_status: :failed)
      expect(conversation.reload.follow_up_badge).to include(step: 1, state: 'failed')
    end

    it 'shows the FUP in progress out of the FUPs the account runs' do
      account.update!(settings: account.settings.merge('follow_up' => { 'steps' => [240, 480, 4320] }))
      create(:follow_up, conversation: conversation, step: 2, delay_minutes: 480, delivery_status: :sent)

      expect(conversation.reload.follow_up_badge).to include(step: 2, total: 3, delay_minutes: 480, delivery_status: 'sent', state: 'running')
    end

    it 'falls back to the current step when the account has no FUP setup' do
      create(:follow_up, conversation: conversation, step: 2)

      expect(conversation.reload.follow_up_badge[:total]).to eq(2)
    end
  end

  it 'refreshes the conversation on the dashboard without running automations' do
    allow(ActionCableListener.instance).to receive(:conversation_updated)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    create(:follow_up, conversation: conversation)

    expect(ActionCableListener.instance).to have_received(:conversation_updated)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_UPDATED, any_args)
  end

  describe 'settling the running FUP' do
    let(:contact) { create(:contact, account: account) }

    def patient_message(**attrs)
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                       message_type: :incoming, sender: contact, **attrs)
    end

    it 'marks the FUP as answered as soon as the patient writes' do
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      patient_message

      expect(follow_up.reload).to have_attributes(outcome: 'reengaged', outcome_at: be_present)
    end

    it 'counts a reaction to the FUP as an answer' do
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      patient_message(content: '👍', content_attributes: { is_reaction: true })

      expect(follow_up.reload.outcome).to eq('reengaged')
    end

    it 'only settles the latest FUP, when it was sent and is still waiting' do
      old = create(:follow_up, conversation: conversation, run_id: 'a', delivery_status: :sent)
      pending = create(:follow_up, conversation: conversation, run_id: 'b')

      patient_message

      expect([old.reload.outcome, pending.reload.outcome]).to eq(%w[waiting waiting])
    end

    it 'keeps a sequence already ended without an answer' do
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent, outcome: :no_response)

      patient_message

      expect(follow_up.reload.outcome).to eq('no_response')
    end

    it 'ignores private notes and messages sent to the patient' do
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      create(:message, conversation: conversation, message_type: :outgoing)
      create(:message, conversation: conversation, message_type: :outgoing, private: true)

      expect(follow_up.reload.outcome).to eq('waiting')
    end

    it 'keeps the answer when the reply also turns the AI off' do
      account.update!(ai_status_uses_attribute: true)
      conversation.inbox.update!(ai_paused: true)
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      patient_message

      expect(conversation.reload.ai_enabled).to be(false)
      expect(follow_up.reload.outcome).to eq('reengaged')
    end

    it 'marks the FUP as interrupted when the AI is turned off' do
      account.update!(ai_status_uses_attribute: true)
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      conversation.set_ai_status!(false)

      expect(follow_up.reload.outcome).to eq('interrupted')
    end

    it 'marks the FUP as interrupted when the agente-off label is added' do
      account.update!(ai_status_uses_attribute: false)
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      conversation.set_ai_status!(false)

      expect(follow_up.reload.outcome).to eq('interrupted')
    end

    it 'marks the FUP as closed when the conversation is resolved' do
      follow_up = create(:follow_up, conversation: conversation, delivery_status: :sent)

      conversation.resolved!

      expect(follow_up.reload.outcome).to eq('closed')
    end
  end

  it 'never rewrites a settled outcome' do
    follow_up = create(:follow_up, conversation: conversation, outcome: :reengaged)
    settled_at = follow_up.outcome_at

    follow_up.update!(outcome: :no_response, delivery_status: :sent)

    expect(follow_up.reload).to have_attributes(outcome: 'reengaged', outcome_at: settled_at, delivery_status: 'sent')
  end
end
