require 'rails_helper'

RSpec.describe AurisConfigs::SupabaseImport do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:dir) { Rails.root.join('tmp', "auris_configs_import_#{SecureRandom.hex(4)}") }
  let(:configuration_csv) { dir.join('configuration.csv') }
  let(:configuration_client_csv) { dir.join('configuration_client.csv') }

  def import(apply: false)
    described_class.new(configuration_csv: configuration_csv, configuration_client_csv: configuration_client_csv, apply: apply).perform
  end

  before do
    FileUtils.mkdir_p(dir)
    CSV.open(configuration_csv, 'w') do |csv|
      csv << %w[id config_key value_type default_value description created_at]
      csv << [1, 'GDrive.RootFolderId', 'string', '1', 'Pasta raiz', '2025-12-11 21:52:46']
      csv << [5, 'Secretaria.BounceSeconds', 'int', '40', 'Bounce padrão', '2025-12-11 21:52:46']
      csv << [6, 'Billing.MaxId', 'int', nil, nil, '2025-12-11 21:52:46']
    end
    CSV.open(configuration_client_csv, 'w') do |csv|
      csv << %w[id client_id configuration_id value created_at]
      csv << [10, account.id, 1, 'pasta-antiga', '2025-12-11 21:52:46']
      csv << [288, account.id, 1, 'pasta-nova', '2025-12-11 21:52:46']
      csv << [11, other_account.id, 1, 'pasta-outra', '2025-12-11 21:52:46']
      csv << [12, 999_999, 1, 'pasta-sem-conta', '2025-12-11 21:52:46']
    end
  end

  after { FileUtils.rm_rf(dir) }

  it 'writes nothing on a dry run and reports what is missing' do
    problems = import

    expect(AurisConfig.count).to eq(0)
    expect(problems).to include('configuração 1 (GDrive.RootFolderId) falta no Rails', "conta #{account.id}, configuração 1: falta no Rails")
  end

  it 'imports the configs with their ids and the latest value of each account key' do
    problems = import(apply: true)

    expect(AurisConfig.order(:id).pluck(:id, :config_key, :default_value))
      .to eq([[1, 'GDrive.RootFolderId', '1'], [5, 'Secretaria.BounceSeconds', '40'], [6, 'Billing.MaxId', nil]])
    expect(AccountAurisConfig.pluck(:account_id, :auris_config_id, :value))
      .to contain_exactly([account.id, 1, 'pasta-nova'], [other_account.id, 1, 'pasta-outra'])
    expect(problems).to eq(['linha 12: conta 999999 não encontrada',
                            "conta #{account.id}, GDrive.RootFolderId repetida no Supabase: fica a linha 288"])
  end

  it 'continues the config ids after the imported ones' do
    import(apply: true)

    expect(create(:auris_config).id).to eq(7)
  end

  it 'replaces the account values on a rerun and then compares clean' do
    import(apply: true)
    AccountAurisConfig.find_by(account: other_account).update!(value: 'mudou')
    AurisConfig.find(5).update!(default_value: '30')

    expect(import).to include("conta #{other_account.id}, configuração 1: valor diferente",
                              'configuração 5 (Secretaria.BounceSeconds) diferente: default_value')

    import(apply: true)

    expect(import).to eq(['linha 12: conta 999999 não encontrada',
                          "conta #{account.id}, GDrive.RootFolderId repetida no Supabase: fica a linha 288"])
  end
end
