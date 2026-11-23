require 'rails_helper'

RSpec.describe Agenda::Sources::GoogleCalendar do
  subject(:source) { described_class.new(integration) }

  let(:integration) { create(:account_integration, config: config) }
  let(:config) { { 'calendar_id' => 'clinica@group.calendar.google.com' } }
  let(:day) { Date.new(2026, 11, 24) }

  def events_url(calendar_id)
    "https://www.googleapis.com/calendar/v3/calendars/#{ERB::Util.url_encode(calendar_id)}/events"
  end

  def stub_events(calendar_id, items, query: hash_including({}), next_page: nil)
    stub_request(:get, events_url(calendar_id)).with(query: query, headers: { 'Authorization' => 'Bearer access-1' })
                                               .to_return(body: { items: items, nextPageToken: next_page }.compact.to_json,
                                                          headers: { 'Content-Type' => 'application/json' })
  end

  def event(id, summary, description: nil, time: '09:00')
    { id: id, summary: summary, description: description,
      start: { dateTime: "2026-11-24T#{time}:00-03:00" }, end: { dateTime: "2026-11-24T#{time.sub(':00', ':30')}:00-03:00" } }
  end

  before do
    allow(Agenda::GoogleConnection).to receive_messages(access_token: 'access-1', email: 'agenda@example.com')
  end

  context 'with a single calendar for the clinic' do
    it 'reads the professional, the procedure and the confirmation from what the AI writes' do
      stub_events('clinica@group.calendar.google.com', [
                    event('e1', '✅ Maria Souza | Consulta | 11999990000',
                          description: 'profissional: Dra. Ana<br>procedimento: Retorno<br>telefone: 11999990000'),
                    event('e2', 'João Lima | Avaliação | 11888880000', description: "profissional: Dr. Beto\ntelefone: 11888880000",
                                                                       time: '10:00'),
                    event('e3', 'Reunião de equipe', time: '11:00'),
                    { id: 'e4', summary: 'Feriado', start: { date: '2026-11-24' }, end: { date: '2026-11-25' } }
                  ], query: hash_including('timeMin' => '2026-11-24T00:00:00-03:00', 'timeMax' => '2026-11-25T00:00:00-03:00',
                                           'singleEvents' => 'true'))

      agenda = source.agenda(day, day)

      expect(agenda[:appointments]).to eq([
                                            { id: 'e1', starts_at: '2026-11-24T09:00:00-03:00', ends_at: '2026-11-24T09:30:00-03:00',
                                              patient_name: 'Maria Souza', professional_id: 'Dra. Ana', professional_name: 'Dra. Ana',
                                              procedure_name: 'Retorno', status: 'confirmed', auris_conversation_id: nil },
                                            { id: 'e2', starts_at: '2026-11-24T10:00:00-03:00', ends_at: '2026-11-24T10:30:00-03:00',
                                              patient_name: 'João Lima', professional_id: 'Dr. Beto', professional_name: 'Dr. Beto',
                                              procedure_name: 'Avaliação', status: 'scheduled', auris_conversation_id: nil },
                                            { id: 'e3', starts_at: '2026-11-24T11:00:00-03:00', ends_at: '2026-11-24T11:30:00-03:00',
                                              patient_name: 'Reunião de equipe', professional_id: nil, professional_name: nil,
                                              procedure_name: nil, status: 'scheduled', auris_conversation_id: nil }
                                          ])
      expect(agenda[:professionals]).to eq([{ id: 'Dra. Ana', name: 'Dra. Ana' }, { id: 'Dr. Beto', name: 'Dr. Beto' }])
      expect(agenda[:complete]).to be(true)
    end

    it 'follows the pages of a busy period' do
      stub_events('clinica@group.calendar.google.com', [event('e1', 'Maria | Consulta | 1')], query: hash_excluding('pageToken'),
                                                                                              next_page: 'p2')
      stub_events('clinica@group.calendar.google.com', [event('e2', 'João | Consulta | 2')], query: hash_including('pageToken' => 'p2'))

      expect(source.agenda(day, day)[:appointments].pluck(:id)).to eq(%w[e1 e2])
    end

    it 'explains a calendar that is not shared with the Google account' do
      stub_request(:get, events_url('clinica@group.calendar.google.com')).with(query: hash_including({})).to_return(status: 404)

      expect { source.agenda(day, day) }
        .to raise_error(Agenda::Source::Error, I18n.t('agenda.errors.calendar_not_shared', calendar: 'clinica@group.calendar.google.com',
                                                                                           email: 'agenda@example.com'))
    end
  end

  context 'with a calendar per professional' do
    let(:config) do
      { 'calendar_id' => 'ignored@group.calendar.google.com',
        'calendars' => [{ 'calendar_id' => 'ana@group.calendar.google.com', 'professional' => 'Dra. Ana' },
                        { 'calendar_id' => 'beto@group.calendar.google.com', 'professional' => '' }] }
    end

    it 'takes the professional from the calendar' do
      stub_events('ana@group.calendar.google.com', [event('a1', 'Maria | Consulta | 1', description: 'profissional: Outro nome')])
      stub_events('beto@group.calendar.google.com', [event('b1', 'João | Consulta | 2')])

      agenda = source.agenda(day, day)

      expect(agenda[:professionals]).to eq([{ id: 'ana@group.calendar.google.com', name: 'Dra. Ana' },
                                            { id: 'beto@group.calendar.google.com', name: 'beto@group.calendar.google.com' }])
      expect(agenda[:appointments].map { |a| a.values_at(:id, :professional_id, :professional_name) })
        .to eq([['a1', 'ana@group.calendar.google.com', 'Dra. Ana'], %w[b1 beto@group.calendar.google.com beto@group.calendar.google.com]])
    end
  end

  it 'explains an integration without a calendar' do
    integration.update!(config: {})

    expect { source.agenda(day, day) }.to raise_error(Agenda::Source::Error, I18n.t('agenda.errors.calendar_missing'))
  end
end
