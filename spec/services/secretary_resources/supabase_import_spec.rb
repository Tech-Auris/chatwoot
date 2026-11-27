require 'rails_helper'

RSpec.describe SecretaryResources::SupabaseImport do
  let(:account) { create(:account) }
  let!(:internal_account) { Account.find_by(id: 150) || create(:account, id: 150) }
  let(:csv_path) { Rails.root.join('tmp', "secretary_resources_import_#{SecureRandom.hex(4)}.csv") }

  before do
    (1..6).each { |id| SecretaryResourceType.find_or_create_by!(id: id) { |type| type.description = "type #{id}" } }
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id created_at cliente_id key resource_type resource_url caption idioma]
      csv << [1, '2026-01-02 10:00:00+00', account.id, 'tabela', 2, 'https://x/tabela.pdf', 'Tabela', nil]
      csv << [2, '2026-01-02 10:00:00+00', account.id, 'tabela', 2, 'https://x/table.pdf', 'Table', 'en']
      csv << [3, '2026-01-02 10:00:00+00', 150, 'endereco', 5, nil, 'Rua X', '']
      csv << [4, '2026-01-02 10:00:00+00', 999_999, 'orfao', 1, 'https://x/a.png', nil, nil]
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the differences in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.find { |result| result.account_id == account.id }.missing.size).to eq(2)
    expect(results.find { |result| result.account_id == 999_999 }.error).to eq('conta não encontrada')
    expect(SecretaryResource.count).to eq(0)
  end

  it "replaces each account's resources, with the cliente id as the account id" do
    create(:secretary_resource, account: account, key: 'antigo')

    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.secretary_resources.pluck(:key, :idioma)).to contain_exactly(%w[tabela en], ['tabela', nil])
    expect(internal_account.secretary_resources.sole).to have_attributes(key: 'endereco', idioma: nil, secretary_resource_type_id: 5)
    expect(results.reject(&:error)).to all(have_attributes(missing: [], extra: []))
  end

  it 'reports a resource changed in Rails after the import' do
    described_class.new(csv_path: csv_path, apply: true).perform
    account.secretary_resources.find_by(idioma: 'en').update!(caption: 'Changed')

    result = described_class.new(csv_path: csv_path).perform.find { |row| row.account_id == account.id }

    expect(result.missing.size).to eq(1)
    expect(result.extra.size).to eq(1)
  end
end
