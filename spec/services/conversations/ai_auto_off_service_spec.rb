require 'rails_helper'

RSpec.describe Conversations::AiAutoOffService do
  let(:account) { create(:account, ai_status_uses_attribute: true) }
  let(:ai_user) { create(:user, account: account, name: 'IA | Auris') }
  let(:agent) { create(:user, account: account) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:inbox) { create(:inbox, account: account, ai_schedule_enabled: true, ai_schedule_team: team) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: ai_user) }

  before do
    InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: ai_user.id.to_s, locked: false)
    GlobalConfig.clear_cache
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    inbox.ai_off_hours.create!(day_of_week: Time.current.in_time_zone(inbox.effective_timezone).wday, from_minutes: 0, to_minutes: 1440)
  end

  def incoming(conv = conversation, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, **attrs)
  end

  it 'hands the conversation to the team and turns the AI off before the webhooks run' do
    incoming

    conversation.reload
    expect(conversation.team).to eq(team)
    expect(conversation.ai_enabled).to be(false)
    expect(conversation.assignee).not_to eq(ai_user)
    expect(AiAssignmentAttempt.last).to have_attributes(conversation_id: conversation.id, reason: 'schedule', team_id: team.id)
  end

  it 'leaves a single activity about the schedule, in the account locale' do
    account.update!(locale: 'pt_BR')

    incoming
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob)

    activities = conversation.messages.activity.pluck(:content)
    expect(activities).to include('IA desligada pelo horário')
    expect(activities).not_to include(I18n.t('conversations.activity.ai_status.disabled_system', locale: 'pt_BR'))
    expect(activities.grep(/IA desligada|AI turned off/).size).to eq(1)
  end

  it 'runs the team round-robin again when the conversation already had the team' do
    conversation.update_columns(team_id: team.id) # rubocop:disable Rails/SkipsModelValidations
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })

    incoming

    expect(conversation.reload.assignee).to eq(agent)
    expect(conversation.ai_enabled).to be(false)
  end

  it 'turns the AI off and leaves the conversation unassigned to a team when none is set' do
    inbox.update!(ai_schedule_team: nil)

    incoming

    expect(conversation.reload.ai_enabled).to be(false)
    expect(conversation.team).to be_nil
  end

  it 'does nothing outside the schedule, when the AI is already off, or for notes, outgoing and group messages' do
    inbox.update!(ai_schedule_enabled: false)
    incoming
    expect(conversation.reload.ai_enabled).to be(true)

    inbox.update!(ai_schedule_enabled: true)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    incoming(private: true)
    expect(conversation.reload.ai_enabled).to be(true)

    group = create(:conversation, account: account, inbox: inbox, group_type: :group)
    incoming(group)
    expect(group.reload.ai_enabled).to be(true)

    conversation.update!(ai_enabled: false, assignee: agent)
    expect { incoming }.not_to(change { conversation.reload.team_id })
  end

  it 'sends the webhook payload with the AI already off' do
    webhook = create(:webhook, account: account, subscriptions: ['message_created'])
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |url, payload, *| payloads << payload if url == webhook.url }

    perform_enqueued_jobs(only: EventDispatcherJob) { incoming }

    expect(payloads.find { |p| p[:event] == 'message_created' }.dig(:conversation, :ai_enabled)).to be(false)
  end

  context 'when the contact has the AI off' do
    before { conversation.contact.update!(ai_disabled: true) }

    it 'turns the AI off without handing the conversation to the team, ahead of the inbox rules' do
      account.update!(locale: 'pt_BR')
      inbox.update!(ai_paused: true)

      incoming
      perform_enqueued_jobs(only: Conversations::ActivityMessageJob)

      expect(conversation.reload.ai_enabled).to be(false)
      expect(conversation.team).to be_nil
      expect(conversation.messages.activity.pluck(:content)).to include('IA desligada para este contato')
    end

    it 'turns it off in a new conversation of the contact too, in any inbox' do
      other_inbox = create(:inbox, account: account)
      other = create(:conversation, account: account, inbox: other_inbox, contact: conversation.contact)

      create(:message, account: account, inbox: other_inbox, conversation: other, message_type: :incoming)

      expect(other.reload.ai_enabled).to be(false)
    end

    it 'leaves group conversations alone' do
      group = create(:conversation, account: account, inbox: inbox, contact: conversation.contact, group_type: :group)

      incoming(group)

      expect(group.reload.ai_enabled).to be(true)
    end
  end

  context 'when the inbox has the AI paused' do
    before { inbox.update!(ai_paused: true, ai_schedule_enabled: false) }

    it 'turns the AI off at any time, without handing the conversation to the team' do
      account.update!(locale: 'pt_BR')

      incoming
      perform_enqueued_jobs(only: Conversations::ActivityMessageJob)

      expect(conversation.reload.ai_enabled).to be(false)
      expect(conversation.team).to be_nil
      expect(conversation.messages.activity.pluck(:content)).to include('IA desligada: a IA está pausada nesta caixa')
    end

    it 'turns the AI off in accounts on the legacy agente-off label' do
      account.update!(ai_status_uses_attribute: false)

      incoming

      expect(conversation.reload.label_list).to include('agente-off')
    end
  end
end
