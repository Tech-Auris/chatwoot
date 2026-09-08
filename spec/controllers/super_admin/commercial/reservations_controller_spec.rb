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

      # Finalized deals (`ganho`/`perdido`) are hidden by default; the screen
      # opens showing what is still moving.
      expect(response.parsed_body['reservations'].pluck('id')).to contain_exactly(negotiating.id)
      expect(response.parsed_body['meta']['applied_status']).to eq('')
    end

    it 'brings back the closed deals when include_finalized is on' do
      get '/super_admin/commercial/reservations/data', params: { include_finalized: '1' }

      expect(response.parsed_body['reservations'].pluck('id')).to contain_exactly(negotiating.id, won.id)
    end

    it 'filters by a chosen status regardless of case' do
      get '/super_admin/commercial/reservations/data', params: { clickup_status: 'GANHO' }

      expect(response.parsed_body['reservations'].pluck('id')).to eq([won.id])
    end

    # A single search box narrows the list by name, clinic, e-mail or
    # phone digits. Matches are case-insensitive; phone is normalized to
    # digits so different masks land on the same row.
    describe 'q filter' do
      let!(:by_name) do
        create(:sales_quote, prospect_name: 'Camila Vieira', clickup_status: 'proposta enviada')
      end
      let!(:by_clinic) do
        create(:sales_quote, prospect_name: 'Outro', company_name: 'Clínica Andorinha', clickup_status: 'proposta enviada')
      end
      let!(:by_email) do
        create(:sales_quote, prospect_email: 'fulano@exemplo.com', clickup_status: 'proposta enviada')
      end
      let!(:by_phone) do
        create(:sales_quote, prospect_phone: '(11) 91234-5678', clickup_status: 'proposta enviada')
      end

      it 'matches on the prospect name' do
        get '/super_admin/commercial/reservations/data', params: { q: 'camila' }

        expect(response.parsed_body['reservations'].pluck('id')).to eq([by_name.id])
      end

      it 'matches on the clinic name (company_name)' do
        get '/super_admin/commercial/reservations/data', params: { q: 'Andorinha' }

        expect(response.parsed_body['reservations'].pluck('id')).to eq([by_clinic.id])
      end

      it 'matches on the e-mail' do
        get '/super_admin/commercial/reservations/data', params: { q: 'exemplo.com' }

        expect(response.parsed_body['reservations'].pluck('id')).to eq([by_email.id])
      end

      it 'matches on phone digits regardless of the mask' do
        get '/super_admin/commercial/reservations/data', params: { q: '91234' }

        expect(response.parsed_body['reservations'].pluck('id')).to eq([by_phone.id])
      end
    end

    it 'carries the link and the access code the prospect needs' do
      get '/super_admin/commercial/reservations/data', params: { clickup_status: 'negociação' }

      row = response.parsed_body['reservations'].first
      expect(row['public_url']).to include(negotiating.public_token)
      expect(row['access_code']).to eq(negotiating.access_code)
      expect(row['reservation_active']).to be(true)
    end

    it 'marks only a converted proposal as won' do
      get '/super_admin/commercial/reservations/data', params: { include_finalized: '1' }

      by_id = response.parsed_body['reservations'].index_by { |row| row['id'] }
      expect(by_id[won.id]['won']).to be(true)
      expect(by_id[negotiating.id]['won']).to be(false)
    end

    # `details_confirmed` is its own status between `reserved` and
    # `signed`; the row now carries it directly, and the screen reads it
    # straight off the status pill.
    it 'passes the details_confirmed status through to the row' do
      confirmed = create(:sales_quote, status: :details_confirmed, clickup_status: 'em análise')

      get '/super_admin/commercial/reservations/data'

      by_id = response.parsed_body['reservations'].index_by { |row| row['id'] }
      expect(by_id[confirmed.id]['status']).to eq('details_confirmed')
    end

    it 'refreshes the status from clickup before listing' do
      allow(search_service).to receive(:find).and_return({ status: 'proposta enviada' })

      get '/super_admin/commercial/reservations/data'

      expect(negotiating.reload.clickup_status).to eq('proposta enviada')
    end
  end
end
