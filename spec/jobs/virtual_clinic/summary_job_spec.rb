require 'rails_helper'

RSpec.describe VirtualClinic::SummaryJob do
  let(:account) { create(:account, virtual_clinic_enabled: true, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  # Monday, 1 December 2026, 8h in São Paulo.
  let(:monday_first) { ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 12, 1, 8, 5) }

  before do
    home = instance_double(V2::Reports::HomeBuilder)
    allow(V2::Reports::HomeBuilder).to receive(:new).and_return(home)
    allow(home).to receive(:section).with('leads').and_return(leads: { total: 12 })
    allow(home).to receive(:section).with('appointments').and_return(appointments: { total: 4 })
  end

  it 'sends each summary due at the person’s hour, only to them' do
    create(:virtual_clinic_summary, account: account, user: admin, daily: true, weekly: false, monthly: true, hour: 8)

    travel_to(monday_first) { described_class.perform_now }

    alerts = account.virtual_clinic_alerts.where(user: admin)
    expect(alerts.pluck(:rule)).to contain_exactly('daily_summary', 'monthly_summary')
    expect(alerts.find_by(rule: 'monthly_summary').payload).to include('leads' => 12, 'appointments' => 4)
    expect(Notification.where(user: admin, notification_type: :virtual_clinic_alert).count).to eq(2)
    message = I18n.with_locale(:pt_BR) { alerts.find_by(rule: 'daily_summary').message }
    expect(message).to eq('Resumo de ontem: 12 leads, 4 agendamentos, 0 conversas novas e 0 follow-ups enviados.')
  end

  it "sends Luciano's summary with the ads of the period, in his chat" do
    rows = [{ conversations_count: 20, spend_cents: 50_000, scheduled_count: 5 },
            { conversations_count: 0, spend_cents: 0, scheduled_count: 0 }]
    allow(V2::Reports::CampaignAnalyticsBuilder).to receive(:new)
      .and_return(instance_double(V2::Reports::CampaignAnalyticsBuilder, build: rows))
    create(:virtual_clinic_summary, account: account, user: admin, persona: :marketing, daily: false, monthly: true, hour: 8)

    travel_to(monday_first) { described_class.perform_now }

    alert = account.virtual_clinic_alerts.find_by!(user: admin)
    expect(alert).to have_attributes(persona: 'marketing', rule: 'marketing_monthly_summary')
    expect(I18n.with_locale(:pt_BR) { alert.message }).to eq(
      'Marketing do mês passado: 1 campanhas ativas, 20 leads de anúncios, 5 agendamentos, R$ 500,00 investidos e R$ 100,00 por agendamento.'
    )
  end

  it 'sends nothing at another hour, twice in the same hour, or to agents' do
    create(:virtual_clinic_summary, account: account, user: admin, hour: 9)
    create(:virtual_clinic_summary, account: account, user: agent, hour: 8)

    travel_to(monday_first) { 2.times { described_class.perform_now } }
    expect(account.virtual_clinic_alerts.count).to eq(0)

    account.virtual_clinic_summaries.find_by(user: admin).update!(hour: 8)
    travel_to(monday_first) { 2.times { described_class.perform_now } }
    expect(account.virtual_clinic_alerts.pluck(:rule)).to eq(['daily_summary'])
  end
end
