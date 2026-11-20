require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::SilentInboxes do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  # A Tuesday at 10h in São Paulo: business hours.
  let(:now) { Time.zone.parse('2026-11-17 13:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  it 'flags a disconnected WhatsApp and a deaf inbox' do
    disconnected = create(:channel_whatsapp, account: account, provider: 'baileys', provider_connection: { 'connection' => 'close' },
                                             validate_provider_config: false, sync_templates: false)
    disconnected.inbox.update!(name: 'WhatsApp 1', secretary_enabled: true)
    deaf = create(:inbox, account: account, name: 'WhatsApp 2', secretary_enabled: true)
    create(:message, account: account, inbox: deaf, message_type: :incoming, created_at: 3.hours.ago)
    busy = create(:inbox, account: account, secretary_enabled: true)
    create(:message, account: account, inbox: busy, message_type: :incoming, created_at: 10.minutes.ago)

    payload = described_class.new(account).payload

    expect(payload[:count]).to eq(2)
    expect(payload[:inboxes]).to contain_exactly({ name: 'WhatsApp 1', reason: 'disconnected' },
                                                 { name: 'WhatsApp 2', reason: 'silent', hours: 3 })
  end
end
