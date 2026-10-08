require 'rails_helper'

RSpec.describe WhatsappSendBlock do
  def channel(provider, provider_connection)
    build(:channel_whatsapp, provider: provider, provider_connection: provider_connection,
                             validate_provider_config: false, sync_templates: false)
  end

  def cloud(health)
    channel('whatsapp_cloud', { 'health' => health })
  end

  it 'lets a connected unofficial number send and stops the others' do
    expect(channel('baileys', { 'connection' => 'open' }).send_block_reason).to be_nil
    expect(channel('zapi', { 'connection' => 'connecting' }).send_block_reason).to eq(:connecting)
    expect(channel('baileys', { 'connection' => 'close' }).send_block_reason).to eq(:disconnected)
  end

  it "follows Meta's health status over the account review" do
    expect(cloud('can_send_message' => 'BLOCKED').send_block_reason).to eq(:meta_blocked)
    expect(cloud('can_send_message' => 'AVAILABLE', 'account_review_status' => 'REJECTED').send_block_reason).to be_nil
    expect(cloud('phone_status' => 'BANNED').send_block_reason).to eq(:banned)
  end

  it 'blocks a restricted number only for what starts a conversation' do
    restricted = cloud('phone_status' => 'RESTRICTED')

    expect(restricted.send_block_reason).to eq(:restricted)
    expect(restricted.send_block_reason(starts_conversation: false)).to be_nil
  end

  it 'lets an official number not read yet send' do
    expect(channel('whatsapp_cloud', {}).send_block_reason).to be_nil
  end

  # Meta's own reason is in English and lives on Saúde da conta; the message
  # stays short and points there.
  it 'explains the reason in a short message when Meta blocks it' do
    blocked = cloud('can_send_message' => 'BLOCKED',
                    'health_errors' => [{ 'error_description' => 'The Business has not passed business verification.' }])

    expect(blocked.send_block_message).to eq(I18n.t('whatsapp_send_block.meta_blocked'))
  end
end
