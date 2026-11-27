require 'rails_helper'

RSpec.describe AurisConfig do
  let(:account) { create(:account) }
  let!(:folder) { create(:auris_config, config_key: 'GDrive.RootFolderId', value_type: 'string', default_value: '1', description: 'Pasta') }
  let!(:bounce) { create(:auris_config, config_key: 'Secretaria.BounceSeconds', value_type: 'int', default_value: '40') }

  # The query n8n's GetConfigurations runs (see the model comment).
  def get_configurations(account_id, key)
    sql = described_class.connection.select_all(<<~SQL.squish, 'GetConfigurations', [account_id, key])
      select c.id as "ConfigId", c.config_key as "ConfigKey", c.value_type as "ValueType",
             c.default_value as "DefaultValue", c.description as "Description",
             a.value is not null as "HasClientValue", a.value as client_value, a.id as client_config_id
      from auris_configs c
      left join account_auris_configs a on a.auris_config_id = c.id and a.account_id = $1
      where coalesce($2, '') = '' or c.config_key = $2
      order by c.id
    SQL
    sql.to_a
  end

  it 'gives n8n every key with the account value next to the default, in the Supabase shape' do
    value = create(:account_auris_config, account: account, auris_config: folder, value: 'pasta-da-clinica')

    expect(get_configurations(account.id, '')).to eq([
                                                       { 'ConfigId' => folder.id, 'ConfigKey' => 'GDrive.RootFolderId', 'ValueType' => 'string',
                                                         'DefaultValue' => '1', 'Description' => 'Pasta', 'HasClientValue' => true,
                                                         'client_value' => 'pasta-da-clinica', 'client_config_id' => value.id },
                                                       { 'ConfigId' => bounce.id, 'ConfigKey' => 'Secretaria.BounceSeconds', 'ValueType' => 'int',
                                                         'DefaultValue' => '40', 'Description' => nil, 'HasClientValue' => false,
                                                         'client_value' => nil, 'client_config_id' => nil }
                                                     ])
  end

  it 'filters by key and ignores other accounts' do
    create(:account_auris_config, auris_config: folder, value: 'de-outra-conta')

    expect(get_configurations(account.id, 'GDrive.RootFolderId'))
      .to contain_exactly(include('ConfigKey' => 'GDrive.RootFolderId', 'HasClientValue' => false, 'client_value' => nil))
  end

  it 'keeps one value per account and key' do
    create(:account_auris_config, account: account, auris_config: folder)

    expect(build(:account_auris_config, account: account, auris_config: folder)).not_to be_valid
  end
end
