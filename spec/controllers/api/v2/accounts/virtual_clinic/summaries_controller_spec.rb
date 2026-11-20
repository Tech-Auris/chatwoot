require 'rails_helper'

RSpec.describe "Virtual clinic Helena's summaries API", type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:manager) { create(:user, account: account, role: :administrator).tap { |user| user.account_users.first.update!(role: :manager) } }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/summary" }

  it 'starts with no summary at 8h' do
    get url, headers: manager.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('daily' => false, 'weekly' => false, 'monthly' => false, 'hour' => 8)
  end

  it 'saves the summaries the person wants and the hour' do
    put url, params: { daily: true, monthly: true, hour: 18 }, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(account.virtual_clinic_summaries.find_by(user: manager)).to have_attributes(daily: true, weekly: false, monthly: true, hour: 18)
  end

  it 'refuses an hour out of the day' do
    put url, params: { daily: true, hour: 30 }, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'is only for administrators and managers' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
