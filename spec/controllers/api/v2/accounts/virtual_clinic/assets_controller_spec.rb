require 'rails_helper'

RSpec.describe 'Virtual clinic assets API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/assets" }
  let(:png) { Rails.root.join('spec/assets/avatar.png').binread }
  let(:assets_dir) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(assets_dir, '1_recepcao'))
    File.binwrite(File.join(assets_dir, '1_recepcao', 'relogio.png'), png)
  end

  after { FileUtils.remove_entry(assets_dir) }

  it 'serves a piece of the clinic art from the local pack to any user of the account' do
    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
      get "#{url}/1_recepcao/relogio.png", headers: agent.create_new_auth_token
    end

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.body.b).to eq(png.b)
    expect(response.headers['Cache-Control']).to include('private')
  end

  it 'serves it from private storage in production' do
    VirtualClinic::AssetStore.upload(assets_dir)

    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: nil do
      get "#{url}/1_recepcao/relogio.png", headers: agent.create_new_auth_token
    end

    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(png.b)
  end

  it 'never leaves the pack folder' do
    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
      get "#{url}/..%2F..%2Fetc/passwd.png", headers: agent.create_new_auth_token
    end

    expect(response).to have_http_status(:not_found)
  end

  it 'is refused when the account is not released' do
    account.update!(virtual_clinic_enabled: false)

    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
      get "#{url}/1_recepcao/relogio.png", headers: agent.create_new_auth_token
    end

    expect(response).to have_http_status(:unauthorized)
  end
end
