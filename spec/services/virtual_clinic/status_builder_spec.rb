require 'rails_helper'

RSpec.describe VirtualClinic::StatusBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ai_user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:builder) { described_class.new(account: account, account_user: account.account_users.find_by(user: admin)) }

  before do
    InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: ai_user.id.to_s, locked: false)
    GlobalConfig.clear_cache
    Rails.cache.clear
  end

  it 'counts the open conversations the AI is handling, ignoring humans and resolved ones' do
    2.times { create(:conversation, account: account, inbox: inbox, assignee: ai_user, status: :open) }
    create(:conversation, account: account, inbox: inbox, assignee: admin, status: :open)
    create(:conversation, account: account, inbox: inbox, assignee: ai_user, status: :resolved)

    expect(builder.build.dig(:secretary, :active_conversations)).to eq(2)
  end

  it 'counts conversations whose latest follow-up is still waiting for the patient' do
    waiting = create(:conversation, account: account, inbox: inbox)
    answered = create(:conversation, account: account, inbox: inbox)
    create(:follow_up, conversation: waiting, run_id: 'a', step: 1, delivery_status: :sent, created_at: 2.hours.ago)
    create(:follow_up, conversation: answered, run_id: 'b', step: 1, delivery_status: :sent, outcome: :reengaged)

    expect(builder.build.dig(:secretary, :in_follow_up)).to eq(1)
  end

  it 'brings the month numbers of the Home page for the manager' do
    expect(builder.build.dig(:manager, :month)).to include(:leads, :appointments, :conversion_rate)
  end
end
