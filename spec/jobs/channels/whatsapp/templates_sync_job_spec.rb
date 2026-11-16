require 'rails_helper'

RSpec.describe Channels::Whatsapp::TemplatesSyncJob do
  let(:channel_whatsapp) { create(:channel_whatsapp, sync_templates: false) }

  it 'enqueues the job' do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    expect { described_class.perform_later(channel_whatsapp) }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  context 'when called' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
    let!(:sibling) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

    it 'shares the synced list with the other numbers on the same WABA' do
      allow(channel).to receive(:sync_templates).and_return(true)

      described_class.perform_now(channel)

      expect(Channels::Whatsapp::TemplatesCopyJob).to have_been_enqueued.with(sibling, channel)
    end

    it 'only stamps the sync time when Meta refuses the list, so the scheduler waits for the next window' do
      allow(channel).to receive(:sync_templates).and_return(false)
      channel.update_columns(message_templates_last_updated: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now(channel)

      expect(channel.reload.message_templates_last_updated).to be > 1.minute.ago
      expect(Channels::Whatsapp::TemplatesCopyJob).not_to have_been_enqueued
    end
  end
end
