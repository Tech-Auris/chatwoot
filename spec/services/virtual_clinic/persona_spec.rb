require 'rails_helper'

RSpec.describe VirtualClinic::Persona do
  let(:account) { create(:account, name: 'Clínica Sorriso') }
  let(:user) { create(:user, account: account, name: 'Paula') }

  it 'gives each persona its name, model and tool allowlist' do
    secretary = described_class.find!('secretary')
    manager = described_class.find!('manager')

    expect([secretary.name, manager.name]).to eq(%w[Clara Helena])
    expect([secretary.model, manager.model]).to eq(%w[gpt-4.1-mini gpt-5.1])
    expect(secretary.tools).to include('follow_ups_em_andamento')
    expect(secretary.tools).not_to include('funil_resumo', 'conversao_por_campanha')
    expect(manager.tools).to include('agendamentos_resumo', 'horarios_pico', 'conversao_por_campanha')
  end

  it 'renders the prompt with the clinic, the user and the date' do
    prompt = described_class.find!('manager').instructions(account: account, user: user)

    expect(prompt).to include('Você é Helena, a gerente da Clínica Sorriso', 'conversando com Paula')
    expect(prompt).to include('Esse dado ainda não está na Auris.')
    expect(prompt).to include(Time.current.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y'))
  end

  it 'keeps the evaluation questions in tools each persona has' do
    described_class.all.each do |persona|
      questions = YAML.load_file(Rails.root.join("config/virtual_clinic/eval/#{persona.key}.yml"))
      expect(questions.flat_map { |item| item['tools'] } - persona.tools).to be_empty
    end
  end

  it 'refuses an unknown persona' do
    expect { described_class.find!('financeiro') }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
