require 'rails_helper'

RSpec.describe Channels::Whatsapp::HealthSummaryRefreshJob do
  let!(:cloud) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let!(:other_cloud) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  before { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false) }

  it 'refreshes every official API number and keeps going when one fails' do
    failing = instance_double(Whatsapp::HealthService)
    working = instance_double(Whatsapp::HealthService, fetch_health_status: {})
    allow(failing).to receive(:fetch_health_status).and_raise(StandardError, 'token expired')
    allow(Whatsapp::HealthService).to receive(:new).with(cloud).and_return(failing)
    allow(Whatsapp::HealthService).to receive(:new).with(other_cloud).and_return(working)

    described_class.perform_now

    expect(Whatsapp::HealthService).to have_received(:new).twice
    expect(working).to have_received(:fetch_health_status)
  end
end
