require 'rails_helper'

RSpec.describe 'Marketing pixels API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:integration) { create(:marketing_integration, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/marketing_integrations/#{integration.id}/pixels" }

  it 'refuses agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists the pixels without their access token' do
    create(:marketing_pixel, marketing_integration: integration, name: 'Principal', access_token: 'EAAG_secret')

    get url, headers: admin.create_new_auth_token, as: :json

    pixel = response.parsed_body['payload'].first
    expect(pixel).to include('name' => 'Principal', 'status' => 'test_mode', 'access_token_set' => true)
    expect(response.body).not_to include('EAAG_secret')
  end

  it 'adds a pixel with its own token' do
    post url, params: { name: 'Agência', pixel_id: ' 777666 ', access_token: 'EAAG_agency', status: 'active' },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(integration.pixels.last).to have_attributes(name: 'Agência', pixel_id: '777666', access_token: 'EAAG_agency', account_id: account.id)
  end

  it 'explains an invalid pixel without the attribute name' do
    create(:marketing_pixel, marketing_integration: integration, pixel_id: '777666')

    post url, params: { name: 'Repetido', pixel_id: '777666', access_token: 'EAAG' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(I18n.t('errors.marketing_pixel.already_added'))
  end

  it 'keeps the stored token when the update leaves it blank' do
    pixel = create(:marketing_pixel, marketing_integration: integration, access_token: 'EAAG_old')

    patch "#{url}/#{pixel.id}", params: { status: 'disabled', access_token: '' }, headers: admin.create_new_auth_token, as: :json

    expect(pixel.reload).to have_attributes(status: 'disabled', access_token: 'EAAG_old')
  end

  it 'removes a pixel and keeps its dispatch history' do
    pixel = create(:marketing_pixel, marketing_integration: integration)
    dispatch = create(:conversion_event_dispatch, account: account, marketing_pixel: pixel)

    delete "#{url}/#{pixel.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(dispatch.reload.marketing_pixel_id).to be_nil
  end
end
