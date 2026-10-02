require 'rails_helper'

RSpec.describe AiAssigneeSync do
  let(:account) { create(:account, ai_status_uses_attribute: true) }
  let(:ai_user) { create(:user, account: account, name: 'IA | Auris') }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, assignee: nil) }

  before do
    InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: ai_user.id.to_s, locked: false)
    GlobalConfig.clear_cache
  end

  context 'when the account keeps the AI status in the ai_enabled column' do
    it 'turns the AI on when the conversation is assigned to the AI user' do
      conversation.update!(ai_enabled: false)

      conversation.update!(assignee: ai_user)

      expect(conversation.reload.ai_enabled).to be(true)
    end

    it 'turns the AI off when the AI user is replaced by another agent' do
      conversation.update!(assignee: ai_user)

      conversation.update!(assignee: agent)

      expect(conversation.reload.ai_enabled).to be(false)
    end

    it 'turns the AI off when the AI user is unassigned' do
      conversation.update!(assignee: ai_user)

      conversation.update!(assignee: nil)

      expect(conversation.reload.ai_enabled).to be(false)
    end

    it 'leaves the AI status alone when the change does not involve the AI user' do
      conversation.update!(ai_enabled: false)

      conversation.update!(assignee: agent)

      expect(conversation.reload.ai_enabled).to be(false)
    end

    it 'turns the AI on for a conversation created already assigned to the AI user' do
      created = create(:conversation, account: account, assignee: ai_user, ai_enabled: false)

      expect(created.reload.ai_enabled).to be(true)
    end
  end

  context 'when the account still uses the agente-off label' do
    let(:account) { create(:account, ai_status_uses_attribute: false) }

    it 'removes the label on assignment to the AI user and adds it back on unassignment' do
      conversation.update!(label_list: %w[agente-off vip])

      conversation.update!(assignee: ai_user)
      expect(conversation.reload.label_list).to contain_exactly('vip')

      conversation.update!(assignee: agent)
      expect(conversation.reload.label_list).to contain_exactly('vip', 'agente-off')
    end
  end

  context 'when no AI user is configured' do
    before do
      InstallationConfig.find_by(name: 'SECRETARY_AI_USER_ID').update!(value: '')
      GlobalConfig.clear_cache
    end

    it 'does not touch the AI status' do
      conversation.update!(ai_enabled: false)

      conversation.update!(assignee: ai_user)

      expect(conversation.reload.ai_enabled).to be(false)
    end
  end
end
