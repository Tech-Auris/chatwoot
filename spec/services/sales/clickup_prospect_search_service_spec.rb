require 'rails_helper'

RSpec.describe Sales::ClickupProspectSearchService do
  subject(:service) { described_class.new(client: client, list_id: '901317316771') }

  let(:client) { instance_double(Integrations::Clickup::Client) }
  let(:tasks) do
    [
      task(id: '86a1', name: 'Felicia Macedo', email: 'atendimento@fivemarketing.com.br',
           phone: '+5561981402211', clinic: 'Clínica Cinco'),
      task(id: '86a2', name: 'João Pereira', email: 'joao@exemplo.com', phone: '+5511987654321')
    ]
  end
  let(:list_statuses) { ['novo lead', 'negociação', 'GANHO', 'perdido'].map { |status| { 'status' => status } } }

  def task(overrides = {})
    defaults = { email: nil, phone: nil, clinic: nil, status: 'negociação', reservation_due: nil, fbclid: nil }
    merged = defaults.merge(overrides)
    id, name, email, phone, clinic, status, reservation_due, fbclid =
      merged.values_at(:id, :name, :email, :phone, :clinic, :status, :reservation_due, :fbclid)

    {
      'id' => id, 'name' => name, 'url' => "https://app.clickup.com/t/#{id}", 'date_created' => '1791419344534',
      'status' => { 'status' => status, 'color' => '#fff' }, 'list' => { 'id' => '901317316771' },
      'custom_fields' => [
        { 'id' => described_class::EMAIL_FIELD_ID, 'value' => email },
        { 'id' => described_class::PHONE_FIELD_ID, 'value' => phone },
        { 'id' => described_class::CLINIC_FIELD_ID, 'value' => clinic },
        { 'id' => described_class::RESERVATION_DUE_FIELD_ID, 'value' => reservation_due },
        { 'id' => described_class::FBCLID_FIELD_ID, 'value' => fbclid }
      ]
    }
  end

  before do
    Rails.cache.clear
    allow(client).to receive(:get_list).and_return({ 'statuses' => list_statuses })
    allow(client).to receive(:list_tasks).and_return({ 'tasks' => tasks, 'last_page' => true })
  end

  describe '#search' do
    # ClickUp keeps won and lost as open columns of the pipeline. The lost one
    # alone holds thousands of tasks, so asking for it would push live deals
    # past the page limit — the walk asks only for the deals still in play.
    it 'walks only the statuses of deals still in play' do
      service.search('felicia')

      expect(client).to have_received(:list_tasks).with(list_id: '901317316771', page: 0, statuses: ['novo lead', 'negociação'])
    end

    it 'finds by the task name' do
      expect(service.search('felicia').pluck(:task_id)).to eq(['86a1'])
    end

    it 'finds by the clinic name, which is what the operator usually knows' do
      expect(service.search('cinco').pluck(:task_id)).to eq(['86a1'])
    end

    it 'finds by e-mail' do
      expect(service.search('joao@exemplo').pluck(:task_id)).to eq(['86a2'])
    end

    # A phone typed without formatting has to find the formatted one.
    it 'finds by phone digits regardless of formatting' do
      expect(service.search('981402211').pluck(:task_id)).to eq(['86a1'])
    end

    it 'ignores accents and case' do
      expect(service.search('CLINICA').pluck(:task_id)).to eq(['86a1'])
    end

    context 'when the lead name carries a partner brand' do
      let(:tasks) { [task(id: '86ahrvwuz', name: 'Farly Goldincision Leads'), task(id: '86a2', name: 'Farly Souza')] }

      it 'finds by every word typed, in any order' do
        expect(service.search('goldincision farly').pluck(:task_id)).to eq(['86ahrvwuz'])
      end

      it 'finds the brand typed with a space the name does not have' do
        expect(service.search('Gold Incision').pluck(:task_id)).to eq(['86ahrvwuz'])
      end
    end

    it 'answers nothing to an empty term instead of the whole pipeline' do
      expect(service.search('')).to eq([])
    end

    # Typing runs a request per keystroke otherwise; the pipeline is fetched
    # once and reused.
    it 'walks the pipeline only once for repeated searches' do
      service.search('felicia')
      service.search('joão')

      expect(client).to have_received(:list_tasks).once
    end
  end

  describe '#find' do
    it 'returns the prospect behind a task id' do
      expect(service.find('86a2')).to include(name: 'João Pereira', email: 'joao@exemplo.com')
    end

    it 'carries the ad click id and when the lead was created' do
      allow(client).to receive(:list_tasks).and_return({ 'tasks' => [task(id: '86a5', name: 'Ana', fbclid: 'IwAR9')], 'last_page' => true })

      expect(service.find('86a5')).to include(fbclid: 'IwAR9', created_at: 1_791_419_344_534)
    end

    # The reservations report mirrors what happened to a deal, so it has to
    # keep seeing the won and the lost ones the cached walk leaves out.
    it 'reads a closed deal straight from ClickUp' do
      allow(client).to receive(:get_task).with('86a3').and_return(task(id: '86a3', name: 'Fabio Rocha', status: 'GANHO'))

      expect(service.find('86a3')).to include(task_id: '86a3', status: 'GANHO')
    end

    it 'returns nothing for a task outside the pipeline' do
      allow(client).to receive(:get_task).with('86z9').and_return(task(id: '86z9', name: 'Outra').merge('list' => { 'id' => '999' }))

      expect(service.find('86z9')).to be_nil
    end

    it 'reads the reservation deadline from the "Vencimento da Reserva" custom field' do
      epoch_ms = 1_760_000_000_000
      allow(client).to receive(:list_tasks).and_return({
                                                         'tasks' => [task(id: '86a4', name: 'Rita', reservation_due: epoch_ms.to_s)],
                                                         'last_page' => true
                                                       })

      expect(service.find('86a4')).to include(due_date: epoch_ms)
    end
  end

  describe 'pagination' do
    it 'keeps asking for pages until ClickUp says it is the last' do
      allow(client).to receive(:list_tasks).with(hash_including(page: 0))
                                           .and_return({ 'tasks' => [tasks.first], 'last_page' => false })
      allow(client).to receive(:list_tasks).with(hash_including(page: 1))
                                           .and_return({ 'tasks' => [tasks.second], 'last_page' => true })

      expect(service.search('a').length).to eq(2)
    end

    # The walk used to stop at ten pages, and every deal past the thousandth
    # task was silently missing from the picker.
    it 'reaches a deal past the tenth page' do
      allow(client).to receive(:list_tasks) do |page:, **|
        next { 'tasks' => [task(id: '86last', name: 'Farly')], 'last_page' => true } if page == 11

        { 'tasks' => [task(id: "86p#{page}", name: 'Outro')], 'last_page' => false }
      end

      expect(service.search('farly').pluck(:task_id)).to eq(['86last'])
    end
  end

  it 'refuses to guess the pipeline list when nobody configured it' do
    expect { described_class.new(client: client).search('felicia') }
      .to raise_error(described_class::NotConfigured, /pipeline/)
  end
end
