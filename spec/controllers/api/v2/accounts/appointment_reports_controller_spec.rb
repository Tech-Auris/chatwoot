require 'rails_helper'

RSpec.describe 'Appointment reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v2/accounts/#{account.id}/appointment_reports" }
  let(:erp) { create(:erp_source, name: 'Clinicorp') }

  let!(:later) do
    create(:appointment, account: account, conversation: conversation, external_id: 'a', scheduled_for: 3.days.from_now,
                         professional_name: 'Dr. Bruno', status: :confirmed)
  end
  let!(:sooner) do
    create(:appointment, account: account, conversation: conversation, external_id: 'b', scheduled_for: 1.day.from_now,
                         professional_name: 'Dra. Ana', procedure_name: 'Avaliação', erp_source: erp)
  end

  before do
    create(:appointment, account: account, conversation: conversation, external_id: 'c', scheduled_for: 2.days.from_now, status: :canceled)
    create(:appointment, account: account, conversation: conversation, external_id: 'd', scheduled_for: 60.days.from_now)
  end

  it 'is refused to agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists the open appointments of the next 30 days, nearest first, with the filter options' do
    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['rows'].pluck('id')).to eq([sooner.id, later.id])
    expect(body['rows'].first).to include('professional_name' => 'Dra. Ana', 'procedure_name' => 'Avaliação', 'source_name' => 'Clinicorp',
                                          'conversation_id' => conversation.display_id)
    expect(body['filters']).to eq('professionals' => ['Dr. Bruno', 'Dra. Ana'], 'erp_sources' => [{ 'id' => erp.id, 'name' => 'Clinicorp' }])
    expect(body['meta']).to include('total_count' => 2)
  end

  it 'filters by period, professional and ERP' do
    params = { from: 2.days.from_now.to_i, to: 90.days.from_now.to_i, professional: 'Dr. Bruno' }
    get url, params: params, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['rows'].pluck('id')).to eq([later.id])

    get url, params: { erp_source_id: erp.id }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['rows'].pluck('id')).to eq([sooner.id])
  end
end
