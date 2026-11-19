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

  describe 'GET summary' do
    let(:summary_url) { "#{url}/summary" }
    let(:window) { { since: Time.zone.parse('2025-10-01 00:00 -03:00').to_i, until: Time.zone.parse('2025-11-01 00:00 -03:00').to_i } }

    before do
      book = lambda do |external_id, at, status, professional, procedure = nil, created_at: Time.current|
        create(:appointment, account: account, conversation: conversation, external_id: external_id, status: status,
                             scheduled_for: Time.zone.parse(at), professional_name: professional, procedure_name: procedure,
                             created_at: created_at)
      end
      # Sunday night in Brasília, already Monday in UTC.
      book.call('s1', '2025-10-05 22:30 -03:00', :attended, 'Dr. Bruno', 'Avaliação')
      book.call('s2', '2025-10-06 10:00 -03:00', :no_show, 'Dr. Bruno', 'Limpeza')
      book.call('s3', '2025-10-06 11:00 -03:00', :attended, 'Dra. Ana', 'Avaliação')
      book.call('s4', '2025-10-07 09:00 -03:00', :canceled, 'Dra. Ana')
      # Booked inside the period, but the consultation falls after it.
      book.call('s5', '2025-11-20 09:00 -03:00', :attended, 'Dr. Carlos', created_at: Time.zone.parse('2025-10-06 09:00 -03:00'))
    end

    it 'is refused to agents' do
      get summary_url, params: window, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'counts the appointments by consultation date, with the no-show rate, weekdays and top names' do
      get summary_url, params: window, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['totals']).to eq('scheduled' => 0, 'rescheduled' => 0, 'confirmed' => 0, 'attended' => 2, 'no_show' => 1, 'canceled' => 1)
      expect(body['no_show_rate']).to eq(33.33)
      expect(body['by_weekday'].first(3)).to eq([
                                                  { 'weekday' => 0, 'attended' => 1, 'no_show' => 0 },
                                                  { 'weekday' => 1, 'attended' => 1, 'no_show' => 1 },
                                                  { 'weekday' => 2, 'attended' => 0, 'no_show' => 0 }
                                                ])
      expect(body['top_professionals']).to eq([{ 'name' => 'Dr. Bruno', 'count' => 2 }, { 'name' => 'Dra. Ana', 'count' => 2 }])
      expect(body['top_procedures']).to eq([{ 'name' => 'Avaliação', 'count' => 2 }, { 'name' => 'Limpeza', 'count' => 1 }])
    end

    it 'has no no-show rate when nobody attended or missed' do
      get summary_url, params: { since: Time.zone.parse('2025-10-07 00:00 -03:00').to_i, until: Time.zone.parse('2025-10-08 00:00 -03:00').to_i },
                       headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('no_show_rate' => nil, 'top_professionals' => [{ 'name' => 'Dra. Ana', 'count' => 1 }])
    end
  end
end
