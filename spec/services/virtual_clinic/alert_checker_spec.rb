require 'rails_helper'

RSpec.describe VirtualClinic::AlertChecker do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { I18n.with_locale(:pt_BR) { example.run } } }

  before do
    create(:follow_up, conversation: create(:conversation, account: account), delivery_status: :failed)
  end

  def check
    described_class.new(account, rules: [VirtualClinic::Alerts::FailedFollowUps]).perform
  end

  it "raises Clara's hand and updates the open maps" do
    expect { check }.to change(account.virtual_clinic_alerts, :count).by(1)

    alert = account.virtual_clinic_alerts.last
    expect(alert).to have_attributes(persona: 'secretary', rule: 'failed_follow_ups', payload: { 'count' => 1 })
    expect(alert.message).to eq('1 follow-up falhou no envio hoje.')
    counts = { 'secretary' => 1, 'manager' => 0, 'marketing' => 0 }
    expect(ActionCableBroadcastJob).to have_been_enqueued.with([admin.pubsub_token], 'virtual_clinic.alerts.updated',
                                                               { counts: counts, account_id: account.id })
  end

  it 'puts the alert in the notifications of administrators and managers only' do
    check

    notification = admin.notifications.last
    alert = account.virtual_clinic_alerts.last
    expect(notification).to have_attributes(notification_type: 'virtual_clinic_alert', primary_actor: alert)
    expect(notification.push_message_title).to eq('Clara precisa de você na Clínica virtual')
    expect(notification.push_message_body).to eq('Clara: 1 follow-up falhou no envio hoje.')
    expect(agent.notifications).to be_empty
  end

  it 'does not repeat the same alert within 4 hours' do
    check
    travel 3.hours
    expect { check }.not_to change(VirtualClinicAlert, :count)
    travel 2.hours
    expect { check }.to change(VirtualClinicAlert, :count).by(1)
  end

  it 'skips rules that are not due now' do
    travel_to(Time.zone.parse('2026-11-17 02:00 UTC'))
    expect { check }.not_to change(VirtualClinicAlert, :count)
  end
end
