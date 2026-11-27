require 'rails_helper'

RSpec.describe SecretarySpecialScenarios::SupabaseImport do
  let(:account) { create(:account) }
  let!(:internal_account) { Account.find_by(id: 150) || create(:account, id: 150) }
  let(:csv_path) { Rails.root.join('tmp', "secretary_special_scenarios_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id created_at cliente_id name situacao gatilho instrucao]
      csv << [1, '2026-01-02 10:00:00+00', account.id, 'reembolso', 'Pede reembolso', 'reembolso', 'Fale do convênio']
      csv << [2, '2026-01-02 10:00:00+00', account.id, 'gestante', 'Paciente gestante', '', 'Encaminhe à obstetra']
      csv << [3, '2026-01-02 10:00:00+00', 150, 'interno', 'Teste', 'teste', 'Responda teste']
      csv << [4, '2026-01-02 10:00:00+00', 999_999, 'orfao', nil, nil, nil]
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the differences in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.find { |result| result.account_id == account.id }.missing.size).to eq(2)
    expect(results.find { |result| result.account_id == 999_999 }.error).to eq('conta não encontrada')
    expect(SecretarySpecialScenario.count).to eq(0)
  end

  it "replaces each account's scenarios in CSV order, with the cliente id as the account id" do
    create(:secretary_special_scenario, account: account, name: 'antigo')

    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(SecretarySpecialScenario.cache_payload(account.id).pluck(:name, :gatilho)).to eq([%w[reembolso reembolso], ['gestante', nil]])
    expect(internal_account.secretary_special_scenarios.sole).to have_attributes(name: 'interno', instrucao: 'Responda teste')
    expect(results.reject(&:error)).to all(have_attributes(missing: [], extra: []))
  end

  it 'reports a scenario changed in Rails after the import' do
    described_class.new(csv_path: csv_path, apply: true).perform
    account.secretary_special_scenarios.find_by(name: 'gestante').update!(instrucao: 'Mudou')

    result = described_class.new(csv_path: csv_path).perform.find { |row| row.account_id == account.id }

    expect(result.missing.size).to eq(1)
    expect(result.extra.size).to eq(1)
  end
end
