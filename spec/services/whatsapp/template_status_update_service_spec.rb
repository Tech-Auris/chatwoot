require 'rails_helper'

RSpec.describe Whatsapp::TemplateStatusUpdateService do
  let(:cached_templates) do
    [
      {
        'id' => '111',
        'name' => 'confirmacao_agenda',
        'status' => 'PENDING',
        'category' => 'UTILITY',
        'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }]
      },
      {
        'id' => '222',
        'name' => 'lembrete',
        'status' => 'APPROVED',
        'category' => 'UTILITY',
        'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Lembrete: {{1}}' }]
      }
    ]
  end
  let(:channel) do
    create(:channel_whatsapp,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false,
           message_templates: cached_templates,
           message_templates_last_updated: 1.hour.ago)
  end

  describe '#perform' do
    it 'patches the cached template status and touches message_templates_last_updated' do
      # Real payload shape from Meta: status transitions arrive as
      # `event` = APPROVED/PENDING/REJECTED/PAUSED/DISABLED/IN_APPEAL/FLAGGED
      # with the numeric `message_template_id` used to locate the row.
      before_ts = channel.message_templates_last_updated
      payload = {
        'event' => 'REJECTED',
        'message_template_id' => 111,
        'message_template_name' => 'confirmacao_agenda',
        'message_template_language' => 'pt_BR',
        'reason' => 'INVALID_FORMAT'
      }

      described_class.new(channel, payload).perform

      channel.reload
      updated = channel.message_templates.find { |t| t['id'] == '111' }
      untouched = channel.message_templates.find { |t| t['id'] == '222' }

      expect(updated['status']).to eq('REJECTED')
      expect(untouched['status']).to eq('APPROVED')
      expect(channel.message_templates_last_updated).to be > before_ts
    end

    it 'falls back to a full TemplatesSyncJob when the template id is not cached' do
      # New template Meta approved before we had a chance to sync — cache
      # miss must not silently drop the event, otherwise the row never
      # shows up until someone clicks Sync.
      expect(Channels::Whatsapp::TemplatesSyncJob).to receive(:perform_later).with(channel)
      payload = {
        'event' => 'APPROVED',
        'message_template_id' => 999,
        'message_template_name' => 'nunca_vista',
        'message_template_language' => 'pt_BR'
      }

      described_class.new(channel, payload).perform
    end

    it 'no-ops when the channel is nil' do
      expect { described_class.new(nil, { 'event' => 'APPROVED', 'message_template_id' => 111 }).perform }.not_to raise_error
    end

    it 'no-ops when the payload is missing the template id or event' do
      expect(channel).not_to receive(:update!)

      described_class.new(channel, { 'event' => 'APPROVED' }).perform
      described_class.new(channel, { 'message_template_id' => 111 }).perform
    end
  end
end
