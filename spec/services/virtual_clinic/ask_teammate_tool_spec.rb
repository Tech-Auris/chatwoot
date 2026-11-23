require 'rails_helper'

RSpec.describe VirtualClinic::AskTeammateTool do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:manager_thread) { VirtualClinicThread.create!(account: account, user: user, persona: :manager) }
  let(:answer) { manager_thread.messages.create!(role: :assistant, status: :pending) }
  let(:manager) { VirtualClinic::Persona.find!('manager', account: account) }
  let(:secretary) { VirtualClinic::Persona.find!('secretary', account: account) }
  let(:tool) { described_class.new(answer: answer, asker: manager, teammate: secretary) }

  def answer_with(content)
    allow(VirtualClinic::AnswerService).to receive(:new) do |reply, delegated:|
      expect(delegated).to be(true)
      instance_double(VirtualClinic::AnswerService, perform: reply.update!(status: :done, content: content))
    end
  end

  it 'is a tool named after the teammate, describing her area' do
    expect(tool.name).to eq('perguntar_secretary')
    expect(tool.description).to include('Clara (secretária)', 'quem espera resposta')
    expect(tool.params_schema['required']).to eq(['pergunta'])
  end

  it 'asks the teammate in a child thread and returns her answer' do
    answer_with('Agora estou com 7 pacientes.')

    expect(tool.execute(pergunta: 'Quem você está atendendo?')).to eq('Agora estou com 7 pacientes.')

    child = VirtualClinicThread.find_by!(parent_message: answer)
    expect(child).to have_attributes(persona: 'secretary', user: user)
    expect(child.messages.map(&:content)).to eq(['Quem você está atendendo?', 'Agora estou com 7 pacientes.'])
    expect(VirtualClinicThread.current_for(account: account, user: user, persona: :secretary)).not_to eq(child)
  end

  it 'tells the map that the manager went to ask, and came back' do
    answer_with('Ok')

    tool.execute(pergunta: 'Tudo bem?')

    %w[asking done].each do |state|
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(
        [user.pubsub_token], 'virtual_clinic.activity',
        { persona: 'manager', target: 'secretary', state: state, account_id: account.id }
      )
    end
  end

  it 'lets Luciano ask Helena, telling the map he went to her' do
    marketing = VirtualClinic::Persona.find!('marketing', account: account)
    marketing_answer = VirtualClinicThread.create!(account: account, user: user, persona: :marketing)
                                          .messages.create!(role: :assistant, status: :pending)
    ask_manager = described_class.new(answer: marketing_answer, asker: marketing, teammate: manager)
    answer_with('Fechamos o mês com 120 leads.')

    expect(ask_manager.name).to eq('perguntar_manager')
    expect(ask_manager.execute(pergunta: 'Como foi o mês?')).to eq('Fechamos o mês com 120 leads.')
    expect(VirtualClinicThread.find_by!(parent_message: marketing_answer).persona).to eq('manager')
    expect(ActionCableBroadcastJob).to have_been_enqueued.with(
      [user.pubsub_token], 'virtual_clinic.activity',
      { persona: 'marketing', target: 'manager', state: 'asking', account_id: account.id }
    )
  end

  it 'gives up softly when the teammate takes too long or fails' do
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

    expect(tool.execute(pergunta: 'Tudo bem?')).to eq({ error: described_class::NO_ANSWER })
    expect(VirtualClinicThread.find_by!(parent_message: answer).messages.last.status).to eq('failed')
  end
end
