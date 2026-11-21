require 'rails_helper'

RSpec.describe 'Virtual clinic alerts API', type: :request do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/virtual_clinic/alerts" }

  before do
    account.virtual_clinic_alerts.create!(persona: :secretary, rule: 'failed_follow_ups', payload: { count: 2 })
    account.virtual_clinic_alerts.create!(persona: :manager, rule: 'no_show_rate', payload: { rate: 20.0, no_shows: 2, total: 10 })
  end

  it 'lists the open alerts with their message and the count per teammate' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['counts']).to eq('secretary' => 1, 'manager' => 1)
    expect(response.parsed_body['alerts'].pluck('message')).to contain_exactly(
      '2 follow-ups falharam no envio hoje.', 'A taxa de faltas dos últimos 7 dias está em 20.0% (2 de 10 consultas).'
    )
  end

  it "acknowledges a teammate's alerts when they are opened" do
    post "#{url}/acknowledge", params: { persona: 'secretary' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(account.virtual_clinic_alerts.open.pluck(:persona)).to eq(['manager'])
  end

  it 'is only for administrators and managers' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "lets the administrator turn on Helena's good morning" do
    patch "/api/v2/accounts/#{account.id}/virtual_clinic/settings", params: { daily_summary: true }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('daily_summary' => true, 'daily_question_limit' => 60)
    expect(account.reload.settings).to include('virtual_clinic_daily_summary' => true)
  end
end
