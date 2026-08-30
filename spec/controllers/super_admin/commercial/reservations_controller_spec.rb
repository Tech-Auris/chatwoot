require 'rails_helper'

RSpec.describe 'Super Admin Commercial Reservations', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:search_service) { instance_double(Sales::ClickupProspectSearchService) }

  before do
    allow(Sales::ClickupProspectSearchService).to receive(:new).and_return(search_service)
    allow(search_service).to receive(:find) { |task_id| { task_id: task_id, status: 'negociação' } }
    sign_in(super_admin, scope: :super_admin)
  end

  describe 'GET /super_admin/commercial/reservations' do
    it 'renders the screen' do
      get '/super_admin/commercial/reservations'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('CommercialReservationsIndex')
    end
  end

  describe 'GET /super_admin/commercial/reservations/data' do
    let!(:negotiating) { create(:sales_quote, status: :reserved, clickup_status: 'negociação', reserved_until: 5.days.from_now) }
    let!(:won) { create(:sales_quote, status: :converted, clickup_status: 'ganho') }

    # Whatever the team has out is the screen; a status is how they narrow it.
    it 'opens on every proposal' do
      get '/super_admin/commercial/reservations/data'

      expect(response.parsed_body['reservations'].pluck('id')).to contain_exactly(negotiating.id, won.id)
      expect(response.parsed_body['meta']['applied_status']).to eq('')
    end

    it 'filters by a chosen status regardless of case' do
      get '/super_admin/commercial/reservations/data', params: { clickup_status: 'GANHO' }

      expect(response.parsed_body['reservations'].pluck('id')).to eq([won.id])
    end

    it 'carries the link and the access code the prospect needs' do
      get '/super_admin/commercial/reservations/data', params: { clickup_status: 'negociação' }

      row = response.parsed_body['reservations'].first
      expect(row['public_url']).to include(negotiating.public_token)
      expect(row['access_code']).to eq(negotiating.access_code)
      expect(row['reservation_active']).to be(true)
    end

    it 'marks only a converted proposal as won' do
      get '/super_admin/commercial/reservations/data'

      by_id = response.parsed_body['reservations'].index_by { |row| row['id'] }
      expect(by_id[won.id]['won']).to be(true)
      expect(by_id[negotiating.id]['won']).to be(false)
    end

    it 'refreshes the status from clickup before listing' do
      allow(search_service).to receive(:find).and_return({ status: 'proposta enviada' })

      get '/super_admin/commercial/reservations/data'

      expect(negotiating.reload.clickup_status).to eq('proposta enviada')
    end
  end
end
