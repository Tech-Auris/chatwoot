require 'rails_helper'

RSpec.describe 'Z-API webhook token rotation API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'zapi', account: account, sync_templates: false, validate_provider_config: false).tap do |whatsapp|
      whatsapp.update_columns(provider_config: whatsapp.provider_config.merge('instance_id' => 'inst', 'token' => 'tok')) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp/zapi/#{channel.inbox.id}/rotate_webhook_token" }
  let(:zapi_url) { "#{Whatsapp::Providers::WhatsappZapiService::API_BASE_PATH}/instances/inst/token/tok/update-every-webhooks" }

  it 'rejects an unauthenticated request' do
    post path

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an agent' do
    expect { post path, headers: agent.create_new_auth_token, as: :json }
      .not_to(change { channel.reload.provider_config['webhook_verify_token'] })

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a manager' do
    manager = create(:user, account: account, role: :manager)

    post path, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns not found for an inbox that is not Z-API' do
    other = create(:channel_api, account: account)

    post "/api/v1/accounts/#{account.id}/whatsapp/zapi/#{other.inbox.id}/rotate_webhook_token",
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'replaces the token, registers it on Z-API and keeps the old one until the new one is used' do
    stub_request(:put, zapi_url).to_return(status: 200)
    old_token = channel.provider_config['webhook_verify_token']

    post path, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    new_token = channel.reload.provider_config['webhook_verify_token']
    expect(new_token).not_to eq(old_token)
    expect(a_request(:put, zapi_url).with { |req| JSON.parse(req.body)['value'].end_with?("?token=#{new_token}") }).to have_been_made

    allow(Webhooks::WhatsappEventsJob).to receive(:set).and_return(Webhooks::WhatsappEventsJob)
    allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
    webhook = "/webhooks/whatsapp/#{channel.phone_number}"

    post webhook, params: { type: 'ReceivedCallback', token: old_token }
    expect(response).to have_http_status(:ok)
    post webhook, params: { type: 'ReceivedCallback', token: new_token }
    expect(response).to have_http_status(:ok)
    post webhook, params: { type: 'ReceivedCallback', token: old_token }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers unprocessable entity and keeps the token when Z-API refuses' do
    stub_request(:put, zapi_url).to_return(status: 400, body: 'error')

    expect { post path, headers: administrator.create_new_auth_token, as: :json }
      .not_to(change { channel.reload.provider_config['webhook_verify_token'] })

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
