require 'rails_helper'

RSpec.describe 'Virtual clinic layout API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:manager) { create(:user, account: account, role: :agent).tap { |user| user.account_users.first.update!(role: :manager) } }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/layout" }
  let(:assets_dir) { Dir.mktmpdir }
  let(:layout) do
    {
      version: 1,
      items: [{ sprite: '4_copa/geladeira.png', x: 648, y: 332 }],
      rooms: { RECEPTION: 'Recepção Centro' },
      team: { manager: { name: 'Marta', sheet: '8_pessoas/pessoa_01.png', x: 708, y: 90 } }
    }
  end

  before do
    %w[4_copa/geladeira.png 8_pessoas/pessoa_01.png 9_avatar/Body_32x32_07.png 9_avatar/Eyes_32x32_02.png
       9_avatar/Outfit_05_32x32_02.png].each do |path|
      FileUtils.mkdir_p(File.join(assets_dir, File.dirname(path)))
      File.binwrite(File.join(assets_dir, path), 'png')
    end
  end

  after { FileUtils.remove_entry(assets_dir) }

  def put_layout(user, body = layout)
    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
      put url, params: { layout: body }, headers: user.create_new_auth_token, as: :json
    end
  end

  it 'starts with the default clinic' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['layout']).to be_nil
  end

  it 'lets a manager save the clinic, which everyone then sees, and tells the open maps' do
    expect { put_layout(manager) }.to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(event: 'virtual_clinic.layout', data: { account_id: account.id, user_id: manager.id })
    expect(response).to have_http_status(:ok)

    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['layout']).to include('version' => 1, 'rooms' => { 'RECEPTION' => 'Recepção Centro' })
    expect(response.parsed_body['layout'].dig('team', 'manager')).to include('name' => 'Marta', 'x' => 708)
    expect(account.virtual_clinic_layout.updated_by).to eq(manager)
    expect(VirtualClinic::Persona.find!('manager', account: account.reload).name).to eq('Marta')
  end

  it 'saves the look a teammate got in the avatar editor' do
    look = { body: 'Body_32x32_07', eyes: 'Eyes_32x32_02', outfit: 'Outfit_05_32x32_02' }
    put_layout(manager, team: { secretary: { avatar: look, x: 304, y: 87 } })

    expect(response).to have_http_status(:ok)
    expect(account.reload.virtual_clinic_layout.layout.dig('team', 'secretary', 'avatar')).to eq(look.stringify_keys)
  end

  it 'refuses an invalid clinic with the reason' do
    put_layout(manager, layout.merge(items: [{ sprite: '4_copa/geladeira.png', x: 2000, y: 1 }]))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq('Um móvel ficou fora da clínica: 4_copa/geladeira.png.')
    expect(account.reload.virtual_clinic_layout).to be_nil
  end

  it 'does not let agents edit the clinic' do
    put_layout(agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'restores the default clinic' do
    put_layout(manager)
    delete url, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(account.reload.virtual_clinic_layout).to be_nil
    expect(VirtualClinic::Persona.find!('manager', account: account).name).to eq('Helena')
  end

  it 'lists the art the editor can use' do
    with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
      get "/api/v2/accounts/#{account.id}/virtual_clinic/assets", headers: manager.create_new_auth_token, as: :json
    end

    expect(response.parsed_body['paths']).to include('4_copa/geladeira.png', '8_pessoas/pessoa_01.png', '9_avatar/Body_32x32_07.png')
  end
end
