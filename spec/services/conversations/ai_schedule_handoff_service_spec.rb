require 'rails_helper'

RSpec.describe Conversations::AiScheduleHandoffService do
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

  it 'leaves a note about the handoff in the conversation' do
    note = I18n.t('conversations.activity.ai_schedule.handed_to_team', team_name: team.name)

    expect { incoming }.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: note))
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
end
