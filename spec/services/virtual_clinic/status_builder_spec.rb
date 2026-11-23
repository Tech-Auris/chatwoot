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

  describe 'whether Clara is serving patients (the n8n secretary)' do
    it 'is on duty when the account is active and the secretary is set up' do
      create(:account_secretary, account: account, secretary_version: create(:secretary_version))
      inbox.update!(secretary_enabled: true)

      expect(builder.build[:secretary]).to include(on_duty: true, off_duty_reason: nil)
    end

    it 'is on duty when the AI answered a patient lately, even without Super Admin (old webhook, like the SDR)' do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: ai_user, created_at: 6.days.ago)

      expect(builder.build[:secretary]).to include(on_duty: true, off_duty_reason: nil)
    end

    it 'is off duty when neither Super Admin has the secretary nor the AI answered in the last 7 days' do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: ai_user, created_at: 8.days.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin)

      expect(builder.build[:secretary]).to include(on_duty: false, off_duty_reason: 'ai_not_found')
    end

    it 'says why when the account status turns the AI off' do
      create(:account_status, status: :payment_pending, label: 'Sem pagamento')
      account.update!(status: :payment_pending)
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: ai_user)

      expect(builder.build[:secretary]).to include(on_duty: false, off_duty_reason: 'Sem pagamento')
    end
  end

  it 'brings the month numbers of the Home page for the manager' do
    expect(builder.build.dig(:manager, :month)).to include(:leads, :appointments, :conversion_rate)
  end

  describe 'the ads of the month, for Luciano' do
    let(:rows) do
      [{ conversations_count: 10, spend_cents: 30_000, scheduled_count: 4 },
       { conversations_count: 0, spend_cents: 12_000, scheduled_count: 0 },
       { conversations_count: 0, spend_cents: 0, scheduled_count: 0 }]
    end

    before do
      allow(V2::Reports::CampaignAnalyticsBuilder).to receive(:new)
        .and_return(instance_double(V2::Reports::CampaignAnalyticsBuilder, build: rows))
    end

    it 'counts the campaigns that brought leads or spent, and what one appointment cost' do
      expect(builder.build[:marketing]).to eq(active_campaigns: 2, cost_per_appointment: 105.0)
    end

    it 'has no cost per appointment without appointments' do
      rows.first[:scheduled_count] = 0

      expect(builder.build.dig(:marketing, :cost_per_appointment)).to be_nil
    end
  end
end
