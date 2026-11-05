require 'rails_helper'

RSpec.describe Channels::Whatsapp::CoexistenceSyncRequestJob do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'token', 'phone_number_id' => '123456' })
  end
  let(:smb_app_data_url) { %r{graph.facebook.com/v\d+\.\d+/#{channel.provider_config['phone_number_id']}/smb_app_data} }

  before do
    stub_request(:post, smb_app_data_url)
      .to_return(status: 200, body: { messaging_product: 'whatsapp', request_id: 'req' }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'asks Meta for the contacts and then the chat history' do
    described_class.perform_now(channel.id)

    expect(WebMock).to have_requested(:post, smb_app_data_url).with(body: hash_including('sync_type' => 'smb_app_state_sync')).once
    expect(WebMock).to have_requested(:post, smb_app_data_url).with(body: hash_including('sync_type' => 'history')).once

    state = channel.reload.history_import_state
    expect(state['status']).to eq('in_progress')
    expect(state.keys).to include('contacts_requested_at', 'requested_at')
  end

  it 'does not ask again for what Meta already accepted, since each request only works once' do
    channel.update_history_import_state!('contacts_requested_at' => 1.minute.ago.iso8601)

    described_class.perform_now(channel.id)

    expect(WebMock).not_to have_requested(:post, smb_app_data_url).with(body: hash_including('sync_type' => 'smb_app_state_sync'))
    expect(WebMock).to have_requested(:post, smb_app_data_url).with(body: hash_including('sync_type' => 'history')).once
  end
end
