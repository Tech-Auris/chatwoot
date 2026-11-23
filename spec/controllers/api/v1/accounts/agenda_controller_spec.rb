require 'rails_helper'

RSpec.describe 'Agenda API', type: :request do
  let(:erp) { create(:erp_source) }
  let(:account) { create(:account, erp_source: erp, erp_menu_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/agenda" }
  let(:appointment) do
    { id: '10', starts_at: '2026-11-24T09:00:00-03:00', ends_at: '2026-11-24T09:30:00-03:00', patient_name: 'Paciente Teste',
      professional_id: '7', professional_name: 'Dra. Ana', procedure_name: 'Consulta', status: 'confirmed' }
  end
  let(:fake_source) do
    Class.new(Agenda::Source) do
      def professionals = [{ id: '7', name: 'Dra. Ana' }]
    end
  end

  before do
    stub_const('FakeAgendaSource', fake_source)
    stub_const('Agenda::Source::SOURCES', { erp.id => 'FakeAgendaSource' })
  end

  context 'when the account has an integration with its ERP' do
    before { create(:account_integration, account: account, erp_source: erp) }

    it 'returns the professionals and the appointments of the period' do
      allow_any_instance_of(FakeAgendaSource).to receive(:appointments).with(Date.new(2026, 11, 24), Date.new(2026, 11, 30)).and_return([appointment]) # rubocop:disable RSpec/AnyInstance

      get url, params: { from: '2026-11-24', to: '2026-11-30' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['professionals']).to eq([{ 'id' => '7', 'name' => 'Dra. Ana' }])
      expect(body['appointments']).to eq([appointment.stringify_keys])
      expect(body.slice('from', 'to', 'complete')).to eq('from' => '2026-11-24', 'to' => '2026-11-30', 'complete' => true)
    end

    it 'refuses a period longer than a week' do
      get url, params: { from: '2026-11-24', to: '2026-12-01' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an invalid date' do
      get url, params: { from: 'amanhã', to: '2026-11-24' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers 502 with the reason when the ERP fails' do
      allow_any_instance_of(FakeAgendaSource).to receive(:appointments).and_raise(Agenda::Source::Error, 'token inválido') # rubocop:disable RSpec/AnyInstance

      get url, params: { from: '2026-11-24', to: '2026-11-24' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['error']).to include('token inválido')
    end

    it 'flags the account as having an agenda' do
      get "/api/v1/accounts/#{account.id}", headers: create(:user, account: account, role: :administrator).create_new_auth_token, as: :json

      expect(response.parsed_body['agenda_enabled']).to be(true)
    end
  end

  it 'answers 404 and hides the menu while the ERP menu is not released for the account' do
    create(:account_integration, account: account, erp_source: erp)
    account.update!(erp_menu_enabled: false)

    get url, params: { from: '2026-11-24', to: '2026-11-24' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Agenda::Source.available?(account)).to be(false)
  end

  it 'answers 404 when the ERP has no integration in the account' do
    get url, params: { from: '2026-11-24', to: '2026-11-24' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'answers 404 when the account ERP has no agenda source' do
    other = create(:erp_source)
    account.update!(erp_source: other)
    create(:account_integration, account: account, erp_source: other)

    get url, params: { from: '2026-11-24', to: '2026-11-24' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Agenda::Source.available?(account)).to be(false)
  end

  it 'requires a user of the account' do
    get url, params: { from: '2026-11-24', to: '2026-11-24' }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
