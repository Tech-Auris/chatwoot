require 'rails_helper'

RSpec.describe SecretarySpecialScenarios::FlagImport do
  let(:on_account) { create(:account) }
  let(:off_account) { create(:account, allow_dynamic_special_scenario: true) }
  let!(:internal_account) { Account.find_by(id: 151) || create(:account, id: 151) }
  let(:csv_path) { Rails.root.join('tmp', "flag_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id allow_dynamic_special_scenario]
      csv << [on_account.id, 'true']
      csv << [off_account.id, nil]
      csv << [151, 'true']
      csv << [999_999, 'true']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the differences in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.map(&:account_id)).to contain_exactly(on_account.id, off_account.id, 151, 999_999)
    expect(results.find { |result| result.account_id == 999_999 }.error).to eq('conta não encontrada')
    expect(on_account.reload.allow_dynamic_special_scenario).to be_nil
  end

  it 'copies the flag into the account settings, with the cliente id as the account id' do
    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(results.map(&:account_id)).to eq([999_999])
    expect(on_account.reload.settings['allow_dynamic_special_scenario']).to be(true)
    expect(off_account.reload.settings['allow_dynamic_special_scenario']).to be(false)
    expect(internal_account.reload.allow_dynamic_special_scenario).to be(true)
  end
end
