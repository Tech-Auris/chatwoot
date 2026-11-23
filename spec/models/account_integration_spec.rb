require 'rails_helper'

RSpec.describe AccountIntegration do
  let(:account) { create(:account) }
  let(:feegow) { create(:erp_source, :with_fields) }

  it 'allows one integration per account and ERP' do
    create(:account_integration, account: account, erp_source: feegow)

    expect(build(:account_integration, account: account, erp_source: feegow)).not_to be_valid
    expect(build(:account_integration, account: account)).to be_valid
  end

  it "masks the ERP's secret fields, keeping the first 3 and last 4 characters of long ones" do
    integration = build(:account_integration, erp_source: feegow, config: {
                          'access_token' => 'abcdefghij1234', 'token_overrides' => { '1' => 'x' }, 'local_id' => 7, 'extra' => 'abcdefghij1234'
                        })

    expect(integration.masked_config).to eq('access_token' => 'abc••••1234', 'token_overrides' => '••••', 'local_id' => 7,
                                            'extra' => 'abcdefghij1234')
  end

  describe '#config_values=' do
    let(:integration) do
      create(:account_integration, erp_source: feegow, config: { 'access_token' => 'old-token', 'local_id' => 1, 'legacy' => 'x' })
    end

    it 'casts each value to the type of its field and keeps keys the ERP no longer lists' do
      integration.update!(config_values: { 'access_token' => 'new-token', 'local_id' => '42', 'token_overrides' => '{"5": "t"}' })

      expect(integration.reload.config).to eq('access_token' => 'new-token', 'local_id' => 42, 'token_overrides' => { '5' => 't' },
                                              'legacy' => 'x')
    end

    it 'keeps a saved secret when its input comes blank, and clears a blank non-secret' do
      integration.update!(config_values: { 'access_token' => '', 'local_id' => '' })

      expect(integration.reload.config).to include('access_token' => 'old-token', 'local_id' => nil)
    end

    it 'refuses a non-integer number and invalid JSON' do
      expect(integration.update(config_values: { 'local_id' => '4x', 'token_overrides' => '{oops' })).to be(false)
      expect(integration.errors[:config]).to contain_exactly('Local ID precisa ser um número inteiro', 'Token overrides não é um JSON válido')
      expect(integration.reload.config['local_id']).to eq(1)
    end
  end

  it 'logs config changes without their values' do
    integration = create(:account_integration, account: account)

    integration.update!(config: { 'access_token' => 'segredo-novo' })

    logs = ActivityLog.where(auditable_type: 'AccountIntegration', auditable_id: integration.id)
    expect(logs.find_by(action: 'update').audited_changes).to eq('config' => [ActivityLog::FILTERED, ActivityLog::FILTERED])
    expect(logs.pluck(:audited_changes).to_json).not_to include('segredo')
  end

  it "is active when it is the account's ERP" do
    account.update!(erp_source: feegow)

    expect(create(:account_integration, account: account, erp_source: feegow)).to be_active
    expect(create(:account_integration, account: account)).not_to be_active
  end
end
