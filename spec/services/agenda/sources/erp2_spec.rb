require 'rails_helper'

RSpec.describe Agenda::Sources::Erp2 do
  subject(:source) { described_class.new(integration) }

  let(:api) { 'https://erp.example.com/v1/api' }
  let(:erp_source) { create(:erp_source, :with_fields, api_url: "#{api}/") }
  let(:integration) { create(:account_integration, erp_source: erp_source, config: { 'access_token' => 'tok-123' }) }
  let(:day) { Date.new(2026, 11, 24) }
  let(:headers) { { 'x-access-token' => 'tok-123' } }

  def stub_api(path, content, query: hash_including({}), status: 200, success: true)
    stub_request(:get, "#{api}/#{path}").with(query: query, headers: headers)
                                        .to_return(status: status, body: { success: success, content: content }.to_json,
                                                   headers: { 'Content-Type' => 'application/json' })
  end

  def appointment_row(id, patient:, status:, time: '09:00:00', duration: 30)
    { agendamento_id: id, data: '24-11-2026', horario: time, duracao: duration, paciente_id: patient, profissional_id: 25,
      procedimento_id: 3, status_id: status, notas: 'not kept' }
  end

  before do
    stub_api('professional/list', [{ profissional_id: 25, nome: 'Dra. Ana' }, { profissional_id: 26, nome: nil }], query: { ativo: '1' })
    stub_api('procedures/list', [{ procedimento_id: 3, nome: 'Consulta' }])
    rows = [appointment_row(10, patient: 5, status: 7), appointment_row(11, patient: 6, status: 11, time: '10:00:00', duration: 0)]
    stub_api('appoints/search', rows, query: { data_start: '24-11-2026', data_end: '24-11-2026' })
    stub_api('patient/search', { nome: 'Maria Souza' }, query: { paciente_id: '5' })
  end

  it 'reads the period in the agenda shape, with every professional at once' do
    stub_request(:get, "#{api}/patient/search").with(query: { paciente_id: '6' }).to_return(status: 409, body: { success: false }.to_json)

    agenda = source.agenda(day, day)

    expect(agenda[:professionals]).to eq([{ id: '25', name: 'Dra. Ana' }, { id: '26', name: '26' }])
    expect(agenda[:appointments]).to eq([
                                          { id: '10', starts_at: '2026-11-24T09:00:00-03:00', ends_at: '2026-11-24T09:30:00-03:00',
                                            patient_name: 'Maria Souza', professional_id: '25', professional_name: 'Dra. Ana',
                                            procedure_name: 'Consulta', status: 'confirmed', auris_conversation_id: nil },
                                          { id: '11', starts_at: '2026-11-24T10:00:00-03:00', ends_at: nil, patient_name: nil,
                                            professional_id: '25', professional_name: 'Dra. Ana', procedure_name: 'Consulta',
                                            status: 'canceled', auris_conversation_id: nil }
                                        ])
    expect(agenda[:complete]).to be(true)
  end

  it 'leaves the names it could not read for the next request' do
    stub_request(:get, "#{api}/patient/search").with(query: { paciente_id: '6' }).to_return(status: 500)

    agenda = source.agenda(day, day)

    expect(agenda[:appointments].pluck(:patient_name)).to eq(['Maria Souza', nil])
    expect(agenda[:complete]).to be(false)
  end

  it 'keeps patient names cached across requests' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    stub_api('patient/search', { nome: 'João Lima' }, query: { paciente_id: '6' })

    described_class.new(integration).agenda(day, day)
    described_class.new(integration).agenda(day, day)

    expect(a_request(:get, "#{api}/patient/search").with(query: { paciente_id: '5' })).to have_been_made.once
    expect(a_request(:get, "#{api}/appoints/search").with(query: hash_including({}))).to have_been_made.once
  end

  it 'shows the agenda without procedure names when the ERP refuses that list' do
    stub_api('procedures/list', nil, status: 422, success: false)
    stub_api('patient/search', { nome: 'João Lima' }, query: { paciente_id: '6' })

    expect(source.agenda(day, day)[:appointments].pluck(:procedure_name)).to eq([nil, nil])
  end

  it 'explains a refused token' do
    stub_api('appoints/search', nil, status: 401, success: false, query: hash_including({}))

    expect { source.agenda(day, day) }.to raise_error(Agenda::Source::Error, /token/)
  end

  it 'explains when the ERP does not answer' do
    stub_request(:get, "#{api}/appoints/search").with(query: hash_including({})).to_timeout

    expect { source.agenda(day, day) }.to raise_error(Agenda::Source::Error, I18n.t('agenda.errors.unreachable'))
  end

  it 'explains when the API address is not filled in on the ERP' do
    erp_source.update!(api_url: '')

    expect { source.agenda(day, day) }.to raise_error(Agenda::Source::Error, I18n.t('agenda.errors.api_url_missing'))
  end
end
