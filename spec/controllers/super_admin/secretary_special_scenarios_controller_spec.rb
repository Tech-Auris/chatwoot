require 'rails_helper'

RSpec.describe 'Super Admin secretary special scenarios', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:scenario) { create(:secretary_special_scenario, account: account, name: 'reembolso') }

  before { sign_in(super_admin, scope: :super_admin) }

  it "lists an account's scenarios" do
    create(:secretary_special_scenario, name: 'de_outra_conta')

    get '/super_admin/secretary_special_scenarios', params: { search: "account:#{account.id}" }

    expect(response.body).to include('reembolso')
    expect(response.body).not_to include('de_outra_conta')
  end

  it 'creates a scenario and refreshes the account cache' do
    expect do
      post '/super_admin/secretary_special_scenarios', params: {
        secretary_special_scenario: { account_id: account.id, name: 'gestante', situacao: 'Paciente gestante',
                                      gatilho: 'grávida', instrucao: 'Encaminhe para a obstetra.' }
      }
    end.to have_enqueued_job(SecretarySpecialScenarios::RefreshCacheJob).with(account.id)

    expect(account.secretary_special_scenarios.find_by(name: 'gestante')).to have_attributes(instrucao: 'Encaminhe para a obstetra.')
  end

  it 'renders the long texts in wide textareas sized to their content' do
    scenario.update!(instrucao: Array.new(12) { |i| "Passo #{i}" }.join("\n"))

    get "/super_admin/secretary_special_scenarios/#{scenario.id}/edit"

    instrucao = Nokogiri::HTML(response.body).at_css('textarea#secretary_special_scenario_instrucao')
    expect(instrucao['rows']).to eq('13')
    expect(instrucao.ancestors('.feature-container')).to be_present
  end

  it 'edits a scenario' do
    patch "/super_admin/secretary_special_scenarios/#{scenario.id}", params: { secretary_special_scenario: { instrucao: 'Nova instrução' } }

    expect(scenario.reload.instrucao).to eq('Nova instrução')
  end

  it 'removes a scenario and refreshes the account cache' do
    expect do
      delete "/super_admin/secretary_special_scenarios/#{scenario.id}"
    end.to have_enqueued_job(SecretarySpecialScenarios::RefreshCacheJob).with(account.id)

    expect(SecretarySpecialScenario.exists?(scenario.id)).to be(false)
  end
end
