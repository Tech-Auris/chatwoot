require 'rails_helper'

RSpec.describe SecretarySpecialScenarios::RefreshCacheJob do
  let(:account) { create(:account) }
  let(:key) { "cache_supabase_special_scenarios:#{account.id}" }
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379')) }

  before { create(:secretary_special_scenario, account: account, name: 'reembolso', instrucao: 'Fale do convênio') }

  after { redis.del(key) }

  it "writes the account's scenarios to n8n's Redis" do
    with_modified_env N8N_REDIS_URL: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379') do
      described_class.perform_now(account.id)
    end

    expect(JSON.parse(redis.get(key)))
      .to contain_exactly(include('cliente_id' => account.id, 'name' => 'reembolso', 'instrucao' => 'Fale do convênio'))
  end

  it 'writes an empty list when the account has no scenarios left' do
    account.secretary_special_scenarios.delete_all

    with_modified_env N8N_REDIS_URL: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379') do
      described_class.perform_now(account.id)
    end

    expect(redis.get(key)).to eq('[]')
  end

  it 'does nothing without N8N_REDIS_URL' do
    with_modified_env N8N_REDIS_URL: nil do
      described_class.perform_now(account.id)
    end

    expect(redis.get(key)).to be_nil
  end
end
