require 'rails_helper'

RSpec.describe SecretarySpecialScenario do
  let(:account) { create(:account) }

  describe 'name' do
    before { create(:secretary_special_scenario, account: account, name: 'objecao_preco') }

    it 'rejects a name the account already has, ignoring case and surrounding spaces' do
      scenario = build(:secretary_special_scenario, account: account, name: ' Objecao_Preco ')

      expect(scenario).not_to be_valid
      expect(scenario.errors[:name].first).to include('already exists in this account')
    end

    it 'accepts the same name in another account' do
      expect(build(:secretary_special_scenario, name: 'objecao_preco')).to be_valid
    end

    it 'stores the name without surrounding spaces' do
      expect(create(:secretary_special_scenario, account: account, name: ' urgencia ').name).to eq('urgencia')
    end
  end

  describe '.cache_payload' do
    it "builds the n8n cache value for the account's scenarios, oldest first" do
      first = create(:secretary_special_scenario, account: account, name: 'b', gatilho: nil)
      create(:secretary_special_scenario, account: account, name: 'a')
      create(:secretary_special_scenario, name: 'de_outra_conta')

      payload = described_class.cache_payload(account.id)

      expect(payload.map { |row| row[:name] }).to eq(%w[b a])
      expect(JSON.generate(payload.first)).to eq(
        JSON.generate(cliente_id: account.id, name: 'b', situacao: first.situacao, gatilho: nil, instrucao: first.instrucao)
      )
    end
  end

  it 'refreshes the cache of both accounts when a scenario moves' do
    scenario = create(:secretary_special_scenario, account: account)
    other = create(:account)

    expect { scenario.update!(account: other) }
      .to have_enqueued_job(SecretarySpecialScenarios::RefreshCacheJob).with(other.id)
      .and have_enqueued_job(SecretarySpecialScenarios::RefreshCacheJob).with(account.id)
  end
end
