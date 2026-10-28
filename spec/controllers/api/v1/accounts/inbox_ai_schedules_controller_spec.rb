require 'rails_helper'

RSpec.describe 'Inbox AI schedule API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/ai_schedule" }
  let(:params) do
    { enabled: true, team_id: team.id,
      hours: [{ day_of_week: 1, from: '08:00', to: '12:00' }, { day_of_week: 1, from: '13:00', to: '18:00' }] }
  end

  it 'saves the schedule, replacing the ranges, for an administrator' do
    inbox.ai_off_hours.create!(day_of_week: 3, from_minutes: 0, to_minutes: 60)

    patch url, params: params, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(inbox.reload).to have_attributes(ai_schedule_enabled: true, ai_schedule_team_id: team.id)
    expect(inbox.ai_off_hours.pluck(:day_of_week, :from_minutes, :to_minutes)).to eq([[1, 480, 720], [1, 780, 1080]])
    expect(response.parsed_body['hours'].first).to eq('day_of_week' => 1, 'from' => '08:00', 'to' => '12:00')
  end

  it 'lets a manager read and change it' do
    manager = create(:user, account: account)
    manager.account_users.find_by(account: account).update!(role: :manager)

    patch url, params: params, headers: manager.create_new_auth_token, as: :json
    get url, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['enabled']).to be(true)
  end

  it 'refuses an agent' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch url, params: params, headers: agent.create_new_auth_token, as: :json
    expect(inbox.reload.ai_schedule_enabled).to be(false)
  end

  it 'refuses a range that ends before it starts' do
    patch url, params: params.merge(hours: [{ day_of_week: 1, from: '12:00', to: '08:00' }]), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.reload.ai_schedule_enabled).to be(false)
  end
end
