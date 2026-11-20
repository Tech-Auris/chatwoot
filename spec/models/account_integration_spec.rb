require 'rails_helper'

RSpec.describe AccountIntegration do
  let(:account) { create(:account) }
  let(:feegow) { create(:erp_source) }

  it 'allows one integration per account and ERP' do
    create(:account_integration, account: account, erp_source: feegow)

    expect(build(:account_integration, account: account, erp_source: feegow)).not_to be_valid
    expect(build(:account_integration, account: account)).to be_valid
  end

  it 'masks the secrets, keeping the last 4 characters of long ones' do
    integration = build(:account_integration, config: {
                          'access_token' => 'abcdefghij1234', 'senha' => 'curta', 'token_overrides' => { '1' => 'x' },
                          'local_id' => '7', 'app-token' => nil
                        })

    expect(integration.masked_config).to eq('access_token' => '••••1234', 'senha' => '••••', 'token_overrides' => '••••',
                                            'local_id' => '7', 'app-token' => nil)
  end

  it 'edits the config as JSON and refuses invalid JSON or a non-object' do
    integration = create(:account_integration)

    integration.update!(config_json: '{"access_token": "novo", "app-token": "k"}')
    expect(integration.reload.config).to eq('access_token' => 'novo', 'app-token' => 'k')

    expect(integration.update(config_json: '{nope')).to be(false)
    expect(integration.update(config_json: '[1]')).to be(false)
    expect(integration.errors[:config_json]).to be_present
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

  it 'starts a new integration with the keys of the ERP' do
    expect(described_class.template_for(13)).to eq('app-token' => nil, 'link' => nil)
  end
end
