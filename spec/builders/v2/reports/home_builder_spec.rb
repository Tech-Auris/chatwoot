require 'rails_helper'

RSpec.describe V2::Reports::HomeBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'Clínica Centro', enable_auto_assignment: false) }
  let(:other_inbox) { create(:inbox, account: account, name: 'Clínica Sul', enable_auto_assignment: false) }
  let(:booker) { create(:user, account: account) }
  let(:owner) { create(:user, account: account) }
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-11-11 15:00') }
  let(:params) { { since: (now - 6.days).beginning_of_day.to_i, until: now.to_i } }

  before do
    travel_to now
    FunnelStage.find_or_create_by!(name: 'Agendado') { |stage| stage.assign_attributes(position: 40, color: '#000', chart_group: 'Agendamento') }
    FunnelStage.find_or_create_by!(name: 'No-Show') { |stage| stage.assign_attributes(position: 70, color: '#000') }
    FunnelStage.find_or_create_by!(name: 'Comparecimento (ganho)') { |stage| stage.assign_attributes(position: 90, color: '#000') }
  end

  def build(account_user: admin.account_users.first, extra: {})
    described_class.new(account: account, account_user: account_user, params: params.merge(extra)).build
  end

  def section(name, account_user: admin.account_users.first, extra: {})
    described_class.new(account: account, account_user: account_user, params: params.merge(extra)).section(name)
  end

  # Answered by default: a lead only waits when the spec says so.
  def lead(inbox: self.inbox, created_at: now - 1.day, waiting_since: nil, **attrs)
    create(:conversation, account: account, inbox: inbox, created_at: created_at, **attrs).tap do |conversation|
      conversation.update_columns(waiting_since: waiting_since) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def move(conversation, stage, at:, user: nil)
    create(:funnel_stage_change, account: account, conversation_id: conversation.id, inbox: conversation.inbox,
                                 contact: conversation.contact, new_stage: stage, user: user, created_at: at)
  end

  describe '#section' do
    it 'answers the trend line points with every section' do
      V2::Reports::Home::MetricsBuilder::SECTIONS.each do |name|
        expect(section(name)).to include(granularity: :day, buckets: have_attributes(size: 7))
      end
    end

    it 'refuses a section it does not know' do
      expect { section('revenue') }.to raise_error(V2::Reports::Home::MetricsBuilder::UnknownSection)
    end
  end

  describe 'leads' do
    it 'counts new conversations of the period against the period before, without groups' do
      lead(created_at: now - 1.day)
      lead(created_at: now - 2.days)
      lead(created_at: now - 10.days)
      lead(created_at: now - 1.day, group_type: :group)

      leads = section('leads')[:leads]

      expect(leads).to include(total: 2, previous: 1)
      expect(leads[:series].size).to eq(7)
      expect(leads[:series].sum).to eq(2)
    end

    it 'filters by origem' do
      lead(origem: 'Google')
      lead(origem: 'Instagram')

      expect(section('leads', extra: { origem: 'Google' })[:leads][:total]).to eq(1)
    end
  end

  describe 'agendamentos, faltas and comparecimentos' do
    it 'counts bookings and no-shows of the period' do
      conversation = lead
      move(conversation, 'Agendado', at: now - 3.days, user: booker)
      move(conversation, 'No-Show', at: now - 1.day, user: owner)
      move(lead, 'Agendado', at: now - 10.days)

      expect(section('appointments')[:appointments]).to include(total: 1, previous: 1)
      expect(section('outcomes')[:no_shows][:total]).to eq(1)
    end

    it 'counts attendances of the period' do
      conversation = lead
      move(conversation, 'Agendado', at: now - 3.days)
      move(conversation, 'Comparecimento (ganho)', at: now - 1.day)

      expect(section('outcomes')[:attendances][:total]).to eq(1)
    end
  end

  describe 'fora do horário' do
    def at(text) = ActiveSupport::TimeZone['America/Sao_Paulo'].parse(text)

    it 'uses the Auris default for a caixa without its own schedule' do
      lead(created_at: at('2026-11-09 10:00')) # Monday, open
      lead(created_at: at('2026-11-10 19:00')) # Tuesday evening
      lead(created_at: at('2026-11-07 11:00')) # Saturday morning, open
      lead(created_at: at('2026-11-07 13:00')) # Saturday afternoon
      lead(created_at: at('2026-11-08 10:00')) # Sunday

      expect(section('leads')[:off_hours_leads][:total]).to eq(3)
    end

    it "follows the caixa's own schedule when it has one" do
      inbox.update!(working_hours_enabled: true, timezone: 'America/Sao_Paulo')
      inbox.working_hours.find_by(day_of_week: 2).update!(open_hour: 8, open_minutes: 0, close_hour: 20, close_minutes: 0)

      lead(created_at: at('2026-11-10 19:00')) # Tuesday, open until 20h here

      expect(section('leads')[:off_hours_leads][:total]).to eq(0)
    end

    it 'counts bookings made off hours or of leads who arrived off hours' do
      arrived_off = lead(created_at: at('2026-11-10 21:00'))
      booked_off = lead(created_at: at('2026-11-09 10:00'))
      in_hours = lead(created_at: at('2026-11-09 10:00'))
      move(arrived_off, 'Agendado', at: at('2026-11-11 09:00'))
      move(booked_off, 'Agendado', at: at('2026-11-09 22:00'))
      move(in_hours, 'Agendado', at: at('2026-11-09 11:00'))

      expect(section('appointments')[:off_hours_appointments][:total]).to eq(2)
    end
  end

  describe 'follow-up' do
    it 'counts the leads that got a follow-up in the period' do
      followed = lead
      create(:follow_up, conversation: followed, created_at: now - 2.days)
      create(:follow_up, conversation: followed, step: 2, created_at: now - 1.day)
      create(:follow_up, conversation: lead, delivery_status: :failed, created_at: now - 1.day)

      expect(section('follow_up')[:follow_up_leads][:total]).to eq(1)
    end

    it 'splits the bookings by the last follow-up sent before them' do
      after_first = lead
      after_third = lead
      without = lead
      create(:follow_up, conversation: after_first, step: 1, created_at: now - 3.days)
      create(:follow_up, conversation: after_first, step: 2, created_at: now - 1.hour)
      (1..3).each { |step| create(:follow_up, conversation: after_third, step: step, created_at: now - (5 - step).days) }
      move(after_first, 'Agendado', at: now - 2.days, user: booker)
      move(after_third, 'Agendado', at: now - 1.day)
      move(without, 'Agendado', at: now - 1.day)

      result = section('appointments')[:after_follow_up]

      expect(result).to include(total: 2, steps: { first: 1, second: 0, third_or_more: 1 })
      expect(result[:conversations]).to contain_exactly(
        include(id: after_first.display_id, step: 1, booked_by: booker.name),
        include(id: after_third.display_id, step: 3)
      )
    end
  end

  describe 'IA' do
    let(:ai_user) { create(:user, account: account) }

    before { InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: ai_user.id.to_s, locked: false) }

    def ai_reply(conversation)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: ai_user)
    end

    it 'counts the leads the AI acted in, as a share of the leads, and how many it handed off' do
      handed = lead
      kept = lead
      lead
      ai_reply(handed)
      ai_reply(kept)
      create(:message, account: account, inbox: inbox, conversation: lead, message_type: :outgoing, sender: owner)
      AiAssignmentAttempt.create!(account: account, conversation: handed, team: create(:team, account: account), triggered_by: ai_user, reason: :ai)

      metrics = section('ai')

      expect(metrics[:ai_conversations]).to include(total: 2, share: 50.0)
      expect(metrics[:handoff]).to include(rate: 50.0, handed_off: 1, ai_conversations: 2)
    end
  end

  describe 'response time' do
    it 'averages the first responses and splits the AI from the team' do
      ai_user = create(:user, account: account)
      InstallationConfig.where(name: 'SECRETARY_AI_USER_ID').first_or_create!(value: ai_user.id.to_s, locked: false)
      create(:reporting_event, account: account, inbox: inbox, conversation: lead, user: ai_user, value: 10, created_at: now - 1.day)
      create(:reporting_event, account: account, inbox: inbox, conversation: lead, user: owner, value: 300, created_at: now - 1.day)

      expect(section('ai')[:response_time]).to include(average: 155, ai_average: 10, team_average: 300)
    end
  end

  describe 'origins' do
    it 'groups the leads of the period, with the ones without origem together' do
      lead(origem: 'Google')
      lead(origem: 'Google')
      lead(origem: nil)

      expect(section('leads')[:origins]).to eq([{ origem: 'Google', count: 2 }, { origem: '__none__', count: 1 }])
    end
  end

  describe 'today' do
    it 'summarizes today, tomorrow and the leads waiting for an answer' do
      lead(created_at: now - 1.hour)
      waiting = lead(waiting_since: now - 15.minutes)
      lead(waiting_since: now - 5.minutes)
      lead(waiting_since: now - 2.days)
      followed = lead(waiting_since: now - 30.minutes)
      create(:follow_up, conversation: followed)
      move(lead, 'Agendado', at: now - 2.hours)
      create(:appointment, account: account, conversation: lead, scheduled_for: now + 1.day, status: :confirmed)
      create(:appointment, account: account, conversation: lead, scheduled_for: now + 1.day, status: :scheduled)
      create(:appointment, account: account, conversation: lead, scheduled_for: now + 1.day, status: :canceled)

      today = build[:today]

      expect(today).to include(booked: 1, tomorrow: { scheduled: 2, confirmed: 1 })
      expect(today[:new_leads]).to eq(1)
      expect(today[:waiting][:conversations].pluck(:id)).to eq([waiting.display_id])
    end
  end

  describe '#drilldown' do
    def drilldown(metric, account_user: admin.account_users.first, page: 1)
      described_class.new(account: account, account_user: account_user, params: params).drilldown(metric: metric, page: page)
    end

    it "lists the card's conversations, newest first, adding up to the card" do
      older = lead(created_at: now - 3.days, origem: 'Google')
      newer = lead(created_at: now - 1.day)
      lead(created_at: now - 10.days)

      result = drilldown('leads')

      expect(result[:rows].pluck(:id)).to eq([newer.display_id, older.display_id])
      expect(result[:rows].last).to include(origem: 'Google', at: older.created_at.to_i)
      expect(result[:meta]).to include(total_count: section('leads')[:leads][:total])
    end

    it 'names who booked, once per conversation' do
      conversation = lead
      move(conversation, 'Agendado', at: now - 3.days, user: owner)
      move(conversation, 'Agendado', at: now - 1.day, user: booker)

      rows = drilldown('appointments')[:rows]

      expect(rows.size).to eq(1)
      expect(rows.first).to include(detail: booker.name, at: (now - 1.day).to_i)
    end

    it "lists tomorrow's open appointments with their status" do
      create(:appointment, account: account, conversation: lead, scheduled_for: now + 1.day, status: :confirmed)
      create(:appointment, account: account, conversation: lead, scheduled_for: now + 1.day, status: :canceled)

      expect(drilldown('tomorrow')[:rows].pluck(:detail)).to eq(['confirmed'])
    end

    it 'lists the lost leads with their loss reason' do
      reason = create(:loss_reason, name: 'Achou caro')
      create(:funnel_stage_change, account: account, conversation_id: lead.id, inbox: inbox, new_stage: 'Perdido',
                                   loss_reason: reason, created_at: now - 1.day)

      expect(drilldown('losses')[:rows].pluck(:detail)).to eq(['Achou caro'])
    end

    it 'pages through long lists' do
      stub_const('V2::Reports::Home::Drilldown::PER_PAGE', 2)
      3.times { lead }

      expect(drilldown('leads', page: 2)).to include(meta: { current_page: 2, per_page: 2, total_count: 3 })
      expect(drilldown('leads', page: 2)[:rows].size).to eq(1)
    end

    it 'refuses a card it does not know' do
      expect { drilldown('revenue') }.to raise_error(V2::Reports::Home::Drilldown::UnknownMetric)
    end
  end

  describe 'caixas' do
    it 'shows an agent only their caixas, by name' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agent, inbox: inbox)
      other_inbox
      lead(inbox: other_inbox)

      expect(build(account_user: agent.account_users.first)[:available_inboxes]).to eq([{ id: inbox.id, name: 'Clínica Centro' }])
      expect(section('leads', account_user: agent.account_users.first)[:leads][:total]).to eq(0)
    end

    it 'narrows the cards to the picked caixas, ignoring caixas out of reach, but not the day summary' do
      lead(inbox: inbox, created_at: now - 1.hour)
      lead(inbox: other_inbox, created_at: now - 1.hour)
      out_of_reach = create(:inbox)
      extra = { inbox_ids: [other_inbox.id.to_s, out_of_reach.id.to_s] }

      expect(section('leads', extra: extra)[:leads][:total]).to eq(1)
      expect(build(extra: extra)[:today][:new_leads]).to eq(2)
    end
  end
end
