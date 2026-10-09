require 'rails_helper'

RSpec.describe FollowUp do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'Conversation#follow_up_badge' do
    it 'is empty without a FUP waiting for the patient' do
      create(:follow_up, conversation: conversation, outcome: :reengaged)

      expect(conversation.reload.follow_up_badge).to be_nil
    end

    it 'shows the FUP in progress out of the FUPs the account runs' do
      account.update!(settings: account.settings.merge('follow_up' => { 'steps' => [240, 480, 4320] }))
      create(:follow_up, conversation: conversation, step: 2, delay_minutes: 480, delivery_status: :sent)

      expect(conversation.reload.follow_up_badge).to include(step: 2, total: 3, delay_minutes: 480, delivery_status: 'sent')
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
end
