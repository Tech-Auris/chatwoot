require 'rails_helper'

RSpec.describe Channels::Whatsapp::TemplatesCopyJob do
  let(:synced_at) { 10.minutes.ago.change(usec: 0) }
  let(:source) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [{ 'id' => '1', 'name' => 'lembrete', 'status' => 'PENDING',
                                                    'header_media_id' => 'media-of-source', 'header_media_source_url' => 'https://x' }],
                              message_templates_last_updated: synced_at)
  end
  let(:sibling) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [{ 'id' => '9', 'name' => 'removido' }], message_templates_last_updated: 1.day.ago)
  end

  it "replaces the sibling's list with the source's, with the same sync time and without the source's header media ids" do
    described_class.perform_now(sibling, source)

    sibling.reload
    expect(sibling.message_templates).to eq([{ 'id' => '1', 'name' => 'lembrete', 'status' => 'PENDING' }])
    expect(sibling.message_templates_last_updated).to eq(synced_at)
  end

  it 'clears the sibling when the WABA has no templates left' do
    source.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now(sibling, source)

    expect(sibling.reload.message_templates).to eq([])
  end
end
