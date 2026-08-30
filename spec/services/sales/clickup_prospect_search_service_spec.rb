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

  def task(overrides = {})
    id, name, email, phone, clinic, status =
      { email: nil, phone: nil, clinic: nil, status: 'negociação' }.merge(overrides)
                                                                   .values_at(:id, :name, :email, :phone, :clinic, :status)

    {
      'id' => id, 'name' => name, 'url' => "https://app.clickup.com/t/#{id}",
      'status' => { 'status' => status, 'color' => '#fff' },
      'custom_fields' => [
        { 'id' => described_class::EMAIL_FIELD_ID, 'value' => email },
        { 'id' => described_class::PHONE_FIELD_ID, 'value' => phone },
        { 'id' => described_class::CLINIC_FIELD_ID, 'value' => clinic }
      ]
    }
  end

  before do
    Rails.cache.clear
    allow(client).to receive(:list_tasks).and_return({ 'tasks' => tasks, 'last_page' => true })
  end

  describe '#search' do
    # ClickUp keeps won and lost as open columns of the pipeline, so the API
    # still hands them over — building a plan for either makes no sense.
    context 'when the deal is already closed' do
      let(:tasks) do
        [
          task(id: '86a1', name: 'Fabio Rocha', email: 'fabio@exemplo.com', status: 'negociação'),
          task(id: '86a2', name: 'Fabio Rocha', email: 'fabio@exemplo.com', status: 'perdido'),
          task(id: '86a3', name: 'Fabio Rocha', email: 'fabio@exemplo.com', status: 'GANHO')
        ]
      end

      it 'offers only the deals still in play' do
        expect(service.search('fabio').pluck(:task_id)).to eq(['86a1'])
      end

      # The reservations report mirrors what happened to a deal, so it has to
      # keep seeing the won and the lost ones.
      it 'still finds a closed deal by its task id' do
        expect(service.find('86a3')).to include(status: 'GANHO')
      end
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

    it 'returns nothing for a task outside the pipeline' do
      expect(service.find('desconhecida')).to be_nil
    end
  end

  describe 'pagination' do
    it 'keeps asking for pages until ClickUp says it is the last' do
      allow(client).to receive(:list_tasks).with(list_id: anything, page: 0)
                                           .and_return({ 'tasks' => [tasks.first], 'last_page' => false })
      allow(client).to receive(:list_tasks).with(list_id: anything, page: 1)
                                           .and_return({ 'tasks' => [tasks.second], 'last_page' => true })

      expect(service.search('a').length).to eq(2)
    end
  end

  it 'refuses to guess the pipeline list when nobody configured it' do
    expect { described_class.new(client: client).search('felicia') }
      .to raise_error(described_class::NotConfigured, /pipeline/)
  end
end
