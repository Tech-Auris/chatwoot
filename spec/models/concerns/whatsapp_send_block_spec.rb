require 'rails_helper'

RSpec.describe WhatsappSendBlock do
  def channel(provider, provider_connection)
    build(:channel_whatsapp, provider: provider, provider_connection: provider_connection,
                             validate_provider_config: false, sync_templates: false)
  end

  it 'lets a connected unofficial number send and stops the others' do
    expect(channel('baileys', { 'connection' => 'open' }).send_block_reason).to be_nil
    expect(channel('zapi', { 'connection' => 'connecting' }).send_block_reason).to eq(:connecting)
    expect(channel('baileys', { 'connection' => 'close' }).send_block_reason).to eq(:disconnected)
  end

  # Meta has accepted sends while reporting the number as blocked.
  it 'never stops an official number, whatever Meta reports' do
    health = { 'can_send_message' => 'BLOCKED', 'phone_status' => 'BANNED' }

    expect(channel('whatsapp_cloud', { 'health' => health }).send_block_reason).to be_nil
  end

  it 'explains the reason in words' do
    expect(channel('baileys', { 'connection' => 'close' }).send_block_message).to eq(I18n.t('whatsapp_send_block.disconnected'))
  end
end
